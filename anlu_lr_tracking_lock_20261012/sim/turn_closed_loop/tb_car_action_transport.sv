`timescale 1ns/1ps
// Serial-level protocol tests, using an independent TX decoder and bit-banged RX.
module tb_car_action_transport;
    localparam integer CLK_HZ = 1000000;
    localparam integer BAUD = 100000;
    localparam integer BIT_TICKS = CLK_HZ / BAUD;
    reg clk = 0;
    always #500 clk = ~clk;
    reg rst_n = 0;
    reg force_zero = 0;
    reg signed [15:0] cmd_vx = 100;
    reg signed [15:0] cmd_vy = -200;
    reg signed [15:0] cmd_wz = 300;
    reg action_active = 1;
    reg [7:0] action_seq = 8'h37;
    reg signed [15:0] action_angle_cdeg = -9000;
    reg [15:0] action_max_wz_mrad = 1500;
    reg signed [15:0] action_forward_mm_s = 100;
    wire command_tx, frame_sent;
    wire [31:0] frame_count;
    reg status_rx = 1;
    wire status_valid;
    wire [7:0] rx_seq, rx_state, rx_fault;
    wire signed [15:0] rx_progress, rx_error;
    wire [31:0] valid_count, error_count;
    reg tx_done = 0, rx_done = 0;

    car_command_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .SEND_HZ(50)) command_dut (
        .clk(clk), .rst_n(rst_n), .force_zero(force_zero),
        .cmd_vx(cmd_vx), .cmd_vy(cmd_vy), .cmd_wz(cmd_wz),
        .action_active(action_active), .action_seq(action_seq),
        .action_angle_cdeg(action_angle_cdeg), .action_max_wz_mrad(action_max_wz_mrad),
        .action_forward_mm_s(action_forward_mm_s),
        .tx(command_tx), .frame_sent(frame_sent), .frame_count(frame_count)
    );
    car_action_status_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) status_dut (
        .clk(clk), .rst_n(rst_n), .rx(status_rx), .status_valid(status_valid),
        .action_seq(rx_seq), .action_state(rx_state), .action_progress_cdeg(rx_progress),
        .action_error_cdeg(rx_error), .action_fault(rx_fault),
        .valid_count(valid_count), .error_count(error_count)
    );

    reg [7:0] command_bytes [0:351];
    time command_start [0:31];
    integer command_byte_count = 0;
    integer bit_i;
    reg [7:0] observed_byte;
    initial begin
        wait (rst_n);
        forever begin
            @(negedge command_tx);
            if ((command_byte_count % 11) == 0)
                command_start[command_byte_count / 11] = $time;
            repeat (BIT_TICKS + BIT_TICKS / 2) @(posedge clk);
            #1;
            observed_byte[0] = command_tx;
            for (bit_i = 1; bit_i < 8; bit_i = bit_i + 1) begin
                repeat (BIT_TICKS) @(posedge clk);
                #1;
                observed_byte[bit_i] = command_tx;
            end
            repeat (BIT_TICKS) @(posedge clk);
            #1;
            if (command_tx !== 1'b1)
                $fatal(1, "TX stop bit was not high");
            if (command_byte_count >= 352)
                $fatal(1, "Command capture overflow");
            command_bytes[command_byte_count] = observed_byte;
            command_byte_count = command_byte_count + 1;
        end
    end

    task check_command;
        input integer frame_num;
        input [7:0] mode, seq;
        input [15:0] word0, word1, word2;
        integer base, k;
        reg [7:0] bcc;
        begin
            base = frame_num * 11;
            if (command_bytes[base] !== 8'h7b || command_bytes[base+1] !== mode ||
                command_bytes[base+2] !== seq || command_bytes[base+10] !== 8'h7d)
                $fatal(1, "Command frame %0d header/mode/sequence/trailer mismatch", frame_num);
            if ({command_bytes[base+3], command_bytes[base+4]} !== word0 ||
                {command_bytes[base+5], command_bytes[base+6]} !== word1 ||
                {command_bytes[base+7], command_bytes[base+8]} !== word2)
                $fatal(1, "Command frame %0d signed fields or snapshot mismatch", frame_num);
            bcc = 0;
            for (k = 0; k < 9; k = k + 1)
                bcc = bcc ^ command_bytes[base+k];
            if (command_bytes[base+9] !== bcc)
                $fatal(1, "Command frame %0d XOR mismatch", frame_num);
        end
    endtask

    task check_period;
        input integer a, b;
        begin
            if ((command_start[b] - command_start[a]) < 19900000 ||
                (command_start[b] - command_start[a]) > 20100000)
                $fatal(1, "Frames %0d/%0d did not repeat at 50 Hz", a, b);
        end
    endtask

    integer duplicate_i;
    initial begin
        repeat (10) @(negedge clk);
        rst_n = 1;
        // Action values must be captured before the first transmitted byte.
        wait (command_byte_count >= 1);
        @(negedge clk);
        action_seq = 8'h7c;
        action_angle_cdeg = 16'h7b7c;
        action_max_wz_mrad = 16'h7d7e;
        action_forward_mm_s = 16'h8000;
        cmd_vx = 444; cmd_vy = 555; cmd_wz = 666;
        wait (command_byte_count >= 22);
        check_command(0, 8'h10, 8'h37, -16'd9000, 16'd1500, 16'd100);
        check_command(1, 8'h10, 8'h7c, 16'h7b7c, 16'h7d7e, 16'h8000);
        check_period(0, 1);
        wait (command_byte_count >= 33);
        check_command(2, 8'h10, 8'h7c, 16'h7b7c, 16'h7d7e, 16'h8000);
        check_period(1, 2);
        for (duplicate_i = 0; duplicate_i < 11; duplicate_i = duplicate_i + 1)
            if (command_bytes[11+duplicate_i] !== command_bytes[22+duplicate_i])
                $fatal(1, "Keepalive changed sequence or action fields");
        $display("PASS: action mode, signed angle/velocity, all marker payloads, XOR, atomic snapshot, 50 Hz identical keepalive");

        wait (frame_count >= 3);
        @(negedge clk);
        action_active = 0;
        cmd_vx = 16'h7fff; cmd_vy = -200; cmd_wz = 16'h8000;
        wait (command_byte_count >= 44);
        check_command(3, 0, 0, 16'h7fff, -16'd200, 16'h8000);
        check_period(2, 3);

        wait (frame_count >= 4);
        @(negedge clk);
        action_active = 1;
        action_seq = 8'h7d;
        action_angle_cdeg = -4500;
        action_max_wz_mrad = 1200;
        action_forward_mm_s = 100;
        wait (command_byte_count >= 45);
        // A one-clock stop overrides an active action without tearing its frame.
        @(negedge clk);
        force_zero = 1;
        action_seq = 8'h7e;
        action_angle_cdeg = 9000;
        action_forward_mm_s = -100;
        @(negedge clk); force_zero = 0;
        wait (command_byte_count >= 66);
        check_command(4, 8'h10, 8'h7d, -16'd4500, 16'd1200, 16'd100);
        check_command(5, 0, 0, 0, 0, 0);
        if ((command_start[5] - command_start[4]) >= 2000000)
            $fatal(1, "Latched stop waited for heartbeat");

        wait (frame_count >= 6);
        @(negedge clk); force_zero = 1;
        wait (command_byte_count >= 77);
        check_command(6, 0, 0, 0, 0, 0);
        if ((command_start[6] - command_start[5]) >= 2000000)
            $fatal(1, "Idle stop edge waited for heartbeat");
        wait (command_byte_count >= 88);
        check_command(7, 0, 0, 0, 0, 0);
        check_period(6, 7);
        wait (frame_count >= 8);
        @(negedge clk); force_zero = 0;
        wait (command_byte_count >= 99);
        check_command(8, 8'h10, 8'h7e, 16'd9000, 16'd1200, -16'd100);
        wait (frame_count >= 9);
        $display("PASS: legacy speed cancellation, one-clock stop retention, urgent stop while busy/idle, sustained zero priority, action resume");
        tx_done = 1;
    end

    task send_byte;
        input [7:0] value;
        input good_stop;
        integer k;
        begin
            @(negedge clk); status_rx = 0;
            repeat (BIT_TICKS) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                status_rx = value[k];
                repeat (BIT_TICKS) @(negedge clk);
            end
            status_rx = good_stop;
            repeat (BIT_TICKS) @(negedge clk);
            status_rx = 1;
        end
    endtask

    reg [7:0] status_packet [0:10];
    task status_checksum;
        integer k;
        reg [7:0] bcc;
        begin
            bcc = 0;
            for (k = 0; k < 9; k = k + 1)
                bcc = bcc ^ status_packet[k];
            status_packet[9] = bcc;
        end
    endtask

    task make_status;
        input [7:0] seq, state, fault;
        input [15:0] progress, error;
        begin
            status_packet[0] = 8'h7c; status_packet[1] = 8'ha1;
            status_packet[2] = seq; status_packet[3] = state;
            status_packet[4] = progress[15:8]; status_packet[5] = progress[7:0];
            status_packet[6] = error[15:8]; status_packet[7] = error[7:0];
            status_packet[8] = fault; status_packet[10] = 8'h7e;
            status_checksum;
        end
    endtask

    task send_packet;
        input integer omitted_byte;
        integer k;
        begin
            for (k = 0; k < 11; k = k + 1)
                if (k != omitted_byte)
                    send_byte(status_packet[k], 1);
            repeat (20) @(negedge clk);
        end
    endtask

    task check_status;
        input [31:0] expected_count;
        input [7:0] seq, state, fault;
        input [15:0] progress, error;
        begin
            if (valid_count !== expected_count)
                $fatal(1, "Status count expected %0d, got %0d", expected_count, valid_count);
            if (rx_seq !== seq || rx_state !== state || rx_fault !== fault ||
                rx_progress !== progress || rx_error !== error)
                $fatal(1, "Status fields changed incorrectly: seq=%0h state=%0d progress=%0d error=%0d fault=%0d",
                       rx_seq, rx_state, rx_progress, rx_error, rx_fault);
        end
    endtask

    reg status_valid_prev = 0, frame_sent_prev = 0;
    reg [55:0] status_fields_prev = 0;
    reg [31:0] valid_count_prev = 0;
    integer status_pulses = 0, frame_pulses = 0;
    always @(negedge clk) begin
        if (rst_n) begin
            if (status_valid && status_valid_prev)
                $fatal(1, "status_valid exceeded one clock");
            if (frame_sent && frame_sent_prev)
                $fatal(1, "frame_sent exceeded one clock");
            if (!status_valid && {rx_seq, rx_state, rx_progress, rx_error, rx_fault} !== status_fields_prev)
                $fatal(1, "Status outputs changed without validated whole-frame pulse");
            if (status_valid) begin
                if (valid_count !== valid_count_prev + 1)
                    $fatal(1, "Status counter/pulse were not atomic");
                status_pulses = status_pulses + 1;
            end else if (valid_count !== valid_count_prev)
                $fatal(1, "Status counter changed without pulse");
            if (frame_sent)
                frame_pulses = frame_pulses + 1;
        end
        status_valid_prev = status_valid;
        frame_sent_prev = frame_sent;
        status_fields_prev = {rx_seq, rx_state, rx_progress, rx_error, rx_fault};
        valid_count_prev = valid_count;
    end

    integer status_k, state_k, fault_k;
    reg [31:0] errors_before;
    reg [31:0] expected_count = 0;
    initial begin
        wait (rst_n);
        // Payload includes 7B/7C/7D/7E and signed extremes; none resets the parser.
        make_status(8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        @(negedge clk); status_rx = 0;
        @(negedge clk); status_rx = 1;
        repeat (50) @(negedge clk);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count != 0)
            $fatal(1, "Short start-bit glitch was not rejected");
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);

        send_byte(8'h12, 1); send_byte(8'h7b, 1); send_byte(8'h7d, 1); send_byte(8'h7e, 1);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);

        errors_before = error_count;
        status_packet[9] = status_packet[9] ^ 8'h01;
        send_packet(-1);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count <= errors_before)
            $fatal(1, "Corrupt checksum was not counted");
        status_checksum;

        repeat (500) @(negedge clk);
        errors_before = error_count;
        status_packet[10] = 8'h7d;
        send_packet(-1);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count <= errors_before)
            $fatal(1, "Wrong trailer was not counted");
        status_packet[10] = 8'h7e;

        repeat (500) @(negedge clk);
        errors_before = error_count;
        status_packet[1] = 8'ha0; status_checksum;
        send_packet(-1);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count <= errors_before)
            $fatal(1, "Wrong status type was not counted");
        status_packet[1] = 8'ha1; status_checksum;

        repeat (500) @(negedge clk);
        errors_before = error_count;
        status_packet[3] = 6; status_checksum;
        send_packet(-1);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count <= errors_before)
            $fatal(1, "Unknown state was not rejected");
        status_packet[3] = 1; status_packet[8] = 7; status_checksum;
        errors_before = error_count;
        send_packet(-1);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        if (error_count <= errors_before)
            $fatal(1, "Unknown fault was not rejected");
        status_packet[8] = 0; status_checksum;

        // A lost byte and an inserted byte each recover at the following frame.
        send_packet(5);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        for (status_k = 0; status_k < 11; status_k = status_k + 1) begin
            send_byte(status_packet[status_k], 1);
            if (status_k == 4) send_byte(8'h55, 1);
        end
        repeat (20) @(negedge clk);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);

        for (status_k = 0; status_k < 4; status_k = status_k + 1)
            send_byte(status_packet[status_k], 1);
        repeat (500) @(negedge clk);
        for (status_k = 4; status_k < 11; status_k = status_k + 1)
            send_byte(status_packet[status_k], 1);
        repeat (20) @(negedge clk);
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);

        errors_before = error_count;
        for (status_k = 0; status_k < 3; status_k = status_k + 1)
            send_byte(status_packet[status_k], 1);
        send_byte(8'h55, 0);
        repeat (500) @(negedge clk);
        if (error_count <= errors_before)
            $fatal(1, "UART bad stop was not counted");
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        send_packet(-1);
        expected_count = expected_count + 1;
        check_status(expected_count, 8'h7b, 1, 0, 16'h7c7d, 16'h7e80);
        $display("PASS: status atomic publication, duplicate status, marker payloads, junk, BCC/type/tail/enum rejection, dropped/inserted bytes, gap reset, UART error recovery");

        for (state_k = 0; state_k <= 5; state_k = state_k + 1) begin
            make_status(8'h7e, state_k, 0, -16'd9000, 16'h8000);
            send_packet(-1);
            expected_count = expected_count + 1;
            check_status(expected_count, 8'h7e, state_k, 0, -16'd9000, 16'h8000);
        end
        for (fault_k = 0; fault_k <= 6; fault_k = fault_k + 1) begin
            make_status(8'h7d, 5, fault_k, 16'h7fff, -16'd1);
            send_packet(-1);
            expected_count = expected_count + 1;
            check_status(expected_count, 8'h7d, 5, fault_k, 16'h7fff, -16'd1);
        end
        $display("PASS: all six action states, all seven fault codes, signed status extremes");
        rx_done = 1;
    end

    initial begin
        wait (tx_done && rx_done);
        repeat (5) @(negedge clk);
        if (status_pulses != valid_count || frame_pulses != frame_count)
            $fatal(1, "Frame/status pulses disagree with validated counts");
        $display("PASS ACTION TRANSPORT: tx_frames=%0d status_frames=%0d rejected_candidates=%0d", frame_count, valid_count, error_count);
        $finish;
    end
    initial begin
        #250000000;
        $fatal(1, "Action transport simulation timeout");
    end
endmodule
