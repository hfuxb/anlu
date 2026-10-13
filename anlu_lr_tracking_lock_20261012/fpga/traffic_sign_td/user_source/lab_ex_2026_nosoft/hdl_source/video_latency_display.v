`timescale 1ns/1ps
// Hold the latest measured latency for a readable on-screen display.
// Measurement is not averaged or slowed: every I_update saves a full sample.
// Healthy samples are published at a frame boundary after REFRESH_MS; the first
// sample and error/recovery transitions are published immediately. In this
// pipeline conversion finishes near frame start, before the OSD rows are drawn.
module video_latency_display #(
    parameter integer CLK_HZ = 75000000,
    parameter integer REFRESH_MS = 1000,
    parameter integer STALE_MS = 1500
) (
    input wire I_clk,
    input wire I_rst_n,
    input wire I_frame_start,
    input wire [19:0] I_bcd20,
    input wire I_valid,
    input wire I_overflow,
    input wire I_update,
    output reg [19:0] O_bcd20,
    output reg O_valid,
    output reg O_overflow
);
    // The multiplication must be wider than 32 bits: 75 MHz * 1000 ms is 75e9.
    localparam [63:0] REFRESH_RAW = (64'd1 * CLK_HZ * REFRESH_MS + 999) / 1000;
    localparam [63:0] STALE_RAW = (64'd1 * CLK_HZ * STALE_MS + 999) / 1000;
    localparam [63:0] REFRESH_CYCLES = REFRESH_RAW == 0 ? 64'd1 : REFRESH_RAW;
    localparam [63:0] STALE_CYCLES = STALE_RAW == 0 ? 64'd1 : STALE_RAW;

    function integer counter_bits;
        input [63:0] limit;
        reg [63:0] value;
        begin
            value = limit;
            counter_bits = 0;
            while (value != 0) begin
                counter_bits = counter_bits + 1;
                value = value >> 1;
            end
            if (counter_bits == 0) counter_bits = 1;
        end
    endfunction

    localparam integer REFRESH_W = counter_bits(REFRESH_CYCLES);
    localparam integer STALE_W = counter_bits(STALE_CYCLES);
    localparam [REFRESH_W-1:0] REFRESH_LIMIT = REFRESH_CYCLES;
    localparam [REFRESH_W-1:0] REFRESH_LAST = REFRESH_CYCLES - 1;
    localparam [STALE_W-1:0] STALE_LIMIT = STALE_CYCLES;
    localparam [STALE_W-1:0] STALE_LAST = STALE_CYCLES - 1;

    reg [19:0] latest_bcd;
    reg latest_valid;
    reg latest_overflow;
    reg sample_seen;
    reg [REFRESH_W-1:0] refresh_age;
    reg [STALE_W-1:0] update_age;

    // Saturating timers retain "due" until a suitable frame boundary arrives.
    // Compare with N-1 so that timeout/refresh happens on the exact Nth clock
    // after the previous sample/publication, including the N=1 case.
    wire refresh_due = (REFRESH_MS == 0) || (refresh_age >= REFRESH_LAST);
    wire stale_due = sample_seen && (update_age >= STALE_LAST);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            latest_bcd <= 20'd0;
            latest_valid <= 1'b0;
            latest_overflow <= 1'b0;
            sample_seen <= 1'b0;
            refresh_age <= {REFRESH_W{1'b0}};
            update_age <= {STALE_W{1'b0}};
            O_bcd20 <= 20'd0;
            O_valid <= 1'b0;
            O_overflow <= 1'b0;
        end else begin
            if (I_update) begin
                latest_bcd <= I_bcd20;
                latest_valid <= I_valid;
                latest_overflow <= I_overflow;
                sample_seen <= 1'b1;
                update_age <= {STALE_W{1'b0}};
            end else if (sample_seen && update_age < STALE_LIMIT) begin
                update_age <= update_age + 1'b1;
            end

            if (O_valid && !O_overflow && refresh_age < REFRESH_LIMIT)
                refresh_age <= refresh_age + 1'b1;

            if (I_update) begin
                // Faults must not be hidden by the one-second display hold.
                // Recovery is also immediate, rather than showing old dashes.
                if (!I_valid || I_overflow || !O_valid || O_overflow ||
                    REFRESH_MS == 0 || (I_frame_start && refresh_due)) begin
                    O_bcd20 <= I_bcd20;
                    O_valid <= I_valid;
                    O_overflow <= I_overflow;
                    refresh_age <= {REFRESH_W{1'b0}};
                end
            end else if (stale_due) begin
                // A frozen measurement source cannot leave a plausible old
                // number (or an old overflow indicator) indefinitely visible.
                O_bcd20 <= 20'd0;
                O_valid <= 1'b0;
                O_overflow <= 1'b0;
                latest_valid <= 1'b0;
                latest_overflow <= 1'b0;
                sample_seen <= 1'b0;
                refresh_age <= {REFRESH_W{1'b0}};
            end else if (I_frame_start && refresh_due && sample_seen &&
                         latest_valid && !latest_overflow) begin
                O_bcd20 <= latest_bcd;
                O_valid <= latest_valid;
                O_overflow <= latest_overflow;
                refresh_age <= {REFRESH_W{1'b0}};
            end
        end
    end
endmodule
