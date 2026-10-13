`timescale 1ns/1ps
// WHEELTEC relative-turn action status receiver, independent of telemetry RX.
// Frame: 7C A1 seq state progress_hi progress_lo error_hi error_lo fault BCC 7E.
// Progress/error are signed centidegrees; BCC is XOR of bytes 0..8.
// State: 0 idle, 1 accepted, 2 running, 3 done, 4 cancelled, 5 fault.
// Fault: 0 none, 1 parameters, 2 timeout, 3 feedback, 4 disabled, 5 watchdog, 6 busy.
// Sliding-window parsing tolerates payload markers, junk, and dropped bytes.
// Outputs change atomically only for a complete validated status frame.
module car_action_status_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               rx,
    output reg                status_valid,
    output reg  [7:0]         action_seq,
    output reg  [7:0]         action_state,
    output reg signed [15:0]  action_progress_cdeg,
    output reg signed [15:0]  action_error_cdeg,
    output reg  [7:0]         action_fault,
    output reg  [31:0]        valid_count,
    output reg  [31:0]        error_count
);
    function integer counter_width;
        input integer value;
        integer v;
        begin
            v = value - 1;
            counter_width = 0;
            while (v > 0) begin
                counter_width = counter_width + 1;
                v = v >> 1;
            end
            if (counter_width < 1)
                counter_width = 1;
        end
    endfunction

    localparam integer RAW_TICKS = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer BIT_TICKS = (RAW_TICKS < 2) ? 2 : RAW_TICKS;
    localparam integer GAP_TICKS = BIT_TICKS * 40;
    localparam integer GAP_WIDTH = counter_width(GAP_TICKS);

    wire [7:0] uart_data;
    wire uart_valid;
    wire uart_framing_error;
    reg [7:0] rx_window [0:10];
    reg [3:0] fill_count;
    reg [GAP_WIDTH-1:0] gap_timer;
    reg [7:0] candidate_bcc;
    integer i;
    integer j;

    car_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(rx), .data(uart_data),
        .valid(uart_valid), .framing_error(uart_framing_error)
    );

    // Candidate after shift: old window[1..10], followed by uart_data.
    // Bytes 0..8 are old window[1..9], and BCC is old window[10].
    always @* begin
        candidate_bcc = 0;
        for (j = 1; j <= 9; j = j + 1)
            candidate_bcc = candidate_bcc ^ rx_window[j];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_valid <= 1'b0;
            action_seq <= 0;
            action_state <= 0;
            action_progress_cdeg <= 0;
            action_error_cdeg <= 0;
            action_fault <= 0;
            valid_count <= 0;
            error_count <= 0;
            fill_count <= 0;
            gap_timer <= 0;
            for (i = 0; i < 11; i = i + 1)
                rx_window[i] <= 0;
        end else begin
            status_valid <= 1'b0;
            if (uart_framing_error) begin
                fill_count <= 0;
                gap_timer <= 0;
                error_count <= error_count + 1'b1;
            end else if (uart_valid) begin
                gap_timer <= 0;
                for (i = 0; i < 10; i = i + 1)
                    rx_window[i] <= rx_window[i+1];
                rx_window[10] <= uart_data;
                if (fill_count < 11)
                    fill_count <= fill_count + 1'b1;

                if (fill_count >= 10 && rx_window[1] == 8'h7c) begin
                    if (rx_window[2] == 8'ha1 && uart_data == 8'h7e &&
                        candidate_bcc == rx_window[10] &&
                        rx_window[4] <= 8'd5 && rx_window[9] <= 8'd6) begin
                        action_seq <= rx_window[3];
                        action_state <= rx_window[4];
                        action_progress_cdeg <= {rx_window[5], rx_window[6]};
                        action_error_cdeg <= {rx_window[7], rx_window[8]};
                        action_fault <= rx_window[9];
                        status_valid <= 1'b1;
                        valid_count <= valid_count + 1'b1;
                        fill_count <= 0;
                    end else begin
                        error_count <= error_count + 1'b1;
                    end
                end
            end else if (fill_count != 0) begin
                if (gap_timer == GAP_TICKS - 1) begin
                    fill_count <= 0;
                    gap_timer <= 0;
                end else begin
                    gap_timer <= gap_timer + 1'b1;
                end
            end else begin
                gap_timer <= 0;
            end
        end
    end
endmodule
