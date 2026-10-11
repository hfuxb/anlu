`timescale 1ns / 1ps

// 只平滑屏幕结果；车辆控制继续接收未经平滑的逐帧识别结果。
module traffic_sign_display_filter (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_result_valid,
    input  wire [7:0]  I_ascii,
    input  wire        I_bbox_valid,
    input  wire [10:0] I_x_min,
    input  wire [10:0] I_x_max,
    input  wire [9:0]  I_y_min,
    input  wire [9:0]  I_y_max,
    output reg         O_result_valid,
    output reg [7:0]  O_ascii,
    output reg         O_bbox_valid,
    output reg [10:0] O_x_min,
    output reg [10:0] O_x_max,
    output reg [9:0]  O_y_min,
    output reg [9:0]  O_y_max
);
    reg [7:0] pending_ascii;
    reg       pending_valid;
    reg [1:0] miss_count;
    wire recognized = I_bbox_valid &&
                      ((I_ascii == "L") || (I_ascii == "R") || (I_ascii == "S"));

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_result_valid <= 1'b0;
            O_ascii <= "?";
            O_bbox_valid <= 1'b0;
            O_x_min <= 11'd0;
            O_x_max <= 11'd0;
            O_y_min <= 10'd0;
            O_y_max <= 10'd0;
            pending_ascii <= "?";
            pending_valid <= 1'b0;
            miss_count <= 2'd0;
        end
        else begin
            O_result_valid <= I_result_valid;
            if (I_result_valid) begin
                if (recognized) begin
                    miss_count <= 2'd0;
                    if (O_bbox_valid && I_ascii == O_ascii) begin
                        // 同一方向可变远或变近，直接更新有效框。
                        pending_valid <= 1'b0;
                        O_x_min <= I_x_min;
                        O_x_max <= I_x_max;
                        O_y_min <= I_y_min;
                        O_y_max <= I_y_max;
                    end
                    else if (pending_valid && pending_ascii == I_ascii) begin
                        // 新方向或首次目标连续出现两帧才显示。
                        pending_valid <= 1'b0;
                        O_ascii <= I_ascii;
                        O_bbox_valid <= 1'b1;
                        O_x_min <= I_x_min;
                        O_x_max <= I_x_max;
                        O_y_min <= I_y_min;
                        O_y_max <= I_y_max;
                    end
                    else begin
                        pending_valid <= 1'b1;
                        pending_ascii <= I_ascii;
                    end
                end
                else begin
                    pending_valid <= 1'b0;
                    if (O_bbox_valid) begin
                        if (miss_count == 2'd2) begin
                            // 连续三帧未知后清除，避免路牌移走后保留旧方向。
                            miss_count <= 2'd0;
                            O_ascii <= "?";
                            O_bbox_valid <= 1'b0;
                            O_x_min <= 11'd0;
                            O_x_max <= 11'd0;
                            O_y_min <= 10'd0;
                            O_y_max <= 10'd0;
                        end
                        else miss_count <= miss_count + 1'b1;
                    end
                end
            end
        end
    end
endmodule
