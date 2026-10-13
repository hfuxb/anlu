`timescale 1ns/1ps
module tb_latency_display;
    // 75 MHz pixel clock. Default timers below run their full 75 million cycles.
    reg clk = 0;
    always #6.666667 clk = ~clk;
    reg rst = 0;
    reg fs = 0, upd = 0, vin = 0, ov = 0;
    reg [19:0] bin = 0;
    wire [19:0] bout;
    wire vout, oout;
    video_latency_display #(.CLK_HZ(1000), .REFRESH_MS(1000), .STALE_MS(1500)) dut (
        .I_clk(clk), .I_rst_n(rst), .I_frame_start(fs), .I_bcd20(bin),
        .I_valid(vin), .I_overflow(ov), .I_update(upd),
        .O_bcd20(bout), .O_valid(vout), .O_overflow(oout));

    reg zfs = 0, zupd = 0, zvalid = 0, zov = 0;
    reg [19:0] zbin = 0;
    wire [19:0] zbout;
    wire zvout, zoout;
    video_latency_display #(.CLK_HZ(1000), .REFRESH_MS(0), .STALE_MS(10)) zero (
        .I_clk(clk), .I_rst_n(rst), .I_frame_start(zfs), .I_bcd20(zbin),
        .I_valid(zvalid), .I_overflow(zov), .I_update(zupd),
        .O_bcd20(zbout), .O_valid(zvout), .O_overflow(zoout));

    reg dfs = 0, dupd = 0, dvalid = 0, dov = 0;
    reg [19:0] dbin = 0;
    wire [19:0] dbout;
    wire dvout, doout;
    video_latency_display defaults (
        .I_clk(clk), .I_rst_n(rst), .I_frame_start(dfs), .I_bcd20(dbin),
        .I_valid(dvalid), .I_overflow(dov), .I_update(dupd),
        .O_bcd20(dbout), .O_valid(dvout), .O_overflow(doout));

    reg default_done = 0;
    integer checks = 0, cycles = 0, n;
    function [19:0] bcd(input integer value);
        integer j;
        begin
            bcd = 0;
            for (j = 0; j < 5; j = j + 1) begin
                bcd[j*4 +: 4] = value % 10;
                value = value / 10;
            end
        end
    endfunction
    task check(input bit condition, input string message);
        begin
            if (!condition) $fatal(1, "%s", message);
            checks = checks + 1;
        end
    endtask
    task cycle(input bit frame, input bit update, input integer number,
               input bit valid, input bit overflow);
        begin
            @(negedge clk);
            fs = frame; upd = update; bin = bcd(number); vin = valid; ov = overflow;
            @(posedge clk); #0.1;
            cycles = cycles + 1;
        end
    endtask
    task snapshot(input integer number, input bit valid, input bit overflow,
                  input string message);
        begin
            check(bout === bcd(number) && vout === valid && oout === overflow, message);
        end
    endtask
    task zero_cycle(input bit frame, input bit update, input integer number,
                    input bit valid, input bit overflow);
        begin
            @(negedge clk);
            zfs = frame; zupd = update; zbin = bcd(number); zvalid = valid; zov = overflow;
            @(posedge clk); #0.1;
        end
    endtask

    // Full-size default parameter test, including the final two timer clocks.
    // A held measurement stays fresh until 1.5 seconds, while publication is
    // due after exactly 75,000,000 clocks and waits for frame_start.
    initial begin
        wait(rst);
        check(defaults.REFRESH_CYCLES == 75000000,
              "default one-second multiplication overflowed 32 bits");
        check(defaults.STALE_CYCLES == 112500000,
              "default stale timer did not calculate 1.5 seconds");
        check(defaults.REFRESH_W == 27 && defaults.STALE_W == 27,
              "default timers are not minimally sized");
        @(negedge clk); dupd = 1; dvalid = 1; dbin = bcd(111);
        @(posedge clk); #0.1;
        check(dbout === bcd(111) && dvout && !doout, "default first sample not immediate");
        @(negedge clk); dbin = bcd(222);
        @(posedge clk); #0.1;
        check(dbout === bcd(111), "default timer refreshed on its second sample");
        @(negedge clk); dupd = 0;
        wait(defaults.refresh_age == 74999998);
        @(negedge clk); dfs = 1;
        @(posedge clk); #0.1;
        check(dbout === bcd(111), "default one-second timer refreshed one clock early");
        @(posedge clk); #0.1;
        check(dbout === bcd(222) && dvout && !doout,
              "default one-second timer did not publish latest complete sample");
        check(defaults.refresh_age == 0, "default timer did not reset after publication");
        @(negedge clk); dfs = 0;
        default_done = 1;
        $display("DEFAULT TIMER PASS: full 75,000,000 clocks = approximately 1 second at 75 MHz");
    end

    initial begin
        repeat(4) @(negedge clk);
        rst = 1;
        cycle(0, 0, 0, 0, 0);
        snapshot(0, 0, 0, "reset/startup retained stale latency");
        cycle(0, 1, 12345, 1, 0);
        snapshot(12345, 1, 0, "first valid latency did not appear without frame_start");

        // All 999 subsequent frame measurements are saved but do not reset
        // the refresh timer, and no sample may alter a healthy displayed value.
        for (n = 1; n < 1000; n = n + 1) begin
            cycle((n % 17) == 0, 1, n, 1, 0);
            snapshot(12345, 1, 0, "healthy display changed before one-second refresh");
        end
        cycle(0, 1, 4000, 1, 0);
        snapshot(12345, 1, 0, "refresh due changed glyphs away from frame_start");
        cycle(0, 1, 4444, 1, 0);
        snapshot(12345, 1, 0, "due was not held while waiting for a frame");
        cycle(1, 1, 5555, 1, 0);
        snapshot(5555, 1, 0, "simultaneous due/frame/update published an older sample");
        check(dut.refresh_age == 0, "commit did not reset display timer");

        for (n = 1; n < 1000; n = n + 1) begin
            cycle(1, 1, 10000 + n, 1, 0);
            snapshot(5555, 1, 0, "sample updates reset/shortened the new display interval");
        end
        cycle(1, 0, 0, 0, 0);
        snapshot(10999, 1, 0, "due frame did not publish saved latest sample");

        cycle(0, 1, 99999, 0, 0);
        snapshot(99999, 0, 0, "invalid update was hidden by display hold");
        repeat(8) cycle(1, 0, 0, 0, 0);
        snapshot(99999, 0, 0, "old valid value returned after invalidation");
        cycle(0, 1, 88888, 1, 0);
        snapshot(88888, 1, 0, "valid recovery waited for timer or frame_start");
        cycle(0, 1, 99999, 1, 1);
        snapshot(99999, 1, 1, "overflow update was hidden by display hold");
        cycle(0, 1, 77777, 1, 0);
        snapshot(77777, 1, 0, "overflow recovery retained old overflow/value");

        for (n = 1; n < 1500; n = n + 1) begin
            cycle(0, 0, 0, 0, 0);
            snapshot(77777, 1, 0, "stale timeout occurred before 1500 clocks");
        end
        cycle(1, 0, 0, 0, 0);
        snapshot(0, 0, 0, "stale timeout failed, or stale frame republished the old sample");
        cycle(1, 0, 0, 0, 0);
        snapshot(0, 0, 0, "old value was republished after stale timeout");
        cycle(0, 1, 45678, 1, 0);
        snapshot(45678, 1, 0, "fresh source recovery was not immediate");

        // An update on the exact stale deadline takes precedence over expiry.
        repeat(1499) cycle(0, 0, 0, 0, 0);
        cycle(1, 1, 65432, 1, 0);
        snapshot(65432, 1, 0, "fresh update on timeout boundary was incorrectly discarded");
        cycle(0, 1, 99999, 1, 1);
        repeat(1499) cycle(0, 0, 0, 0, 0);
        snapshot(99999, 1, 1, "overflow cleared before its source became stale");
        cycle(0, 0, 0, 0, 0);
        snapshot(0, 0, 0, "stale source retained overflow rather than dashes");

        zero_cycle(0, 1, 10101, 1, 0);
        check(zbout === bcd(10101) && zvout && !zoout,
              "REFRESH_MS=0 first value did not publish immediately");
        zero_cycle(0, 1, 20202, 1, 0);
        check(zbout === bcd(20202) && zvout && !zoout,
              "REFRESH_MS=0 did not preserve per-frame conversion compatibility");
        zero_cycle(0, 1, 99999, 1, 1);
        check(zbout === bcd(99999) && zvout && zoout,
              "REFRESH_MS=0 lost overflow snapshot");
        zero_cycle(0, 1, 30303, 0, 0);
        check(zbout === bcd(30303) && !zvout && !zoout,
              "REFRESH_MS=0 lost invalid snapshot");
        zero_cycle(0, 1, 40404, 1, 0);
        repeat(9) zero_cycle(0, 0, 0, 0, 0);
        check(zbout === bcd(40404) && zvout && !zoout,
              "zero-refresh stale timer expired one clock early");
        zero_cycle(0, 0, 0, 0, 0);
        check(zbout === 0 && !zvout && !zoout, "zero-refresh stale timer did not expire");

        @(negedge clk); fs = 0; upd = 0; zupd = 0;
        wait(default_done);
        @(negedge clk); rst = 0;
        @(posedge clk); #0.1;
        snapshot(0, 0, 0, "reset did not clear published snapshot");
        check(zbout === 0 && !zvout && !zoout && dbout === 0 && !dvout && !doout,
              "reset did not clear all parameter configurations");
        $display("PASS LATENCY DISPLAY %0d checks: latest sample, one-second frame-boundary hold, atomic updates, invalid/overflow recovery, exact stale timeout, REFRESH_MS=0, full 75 MHz default timer", checks);
        $finish;
    end
    initial begin #1100000000; $fatal(1, "latency display test timeout"); end
endmodule
