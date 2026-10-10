`timescale 1ns / 1ps

// 路牌分类和框坐标作为同一稳定负载跨时钟域传送。
// 源域先保持完整负载，再翻转toggle；目标域等待总线稳定后一次捕获。
module traffic_sign_result_cdc (
    input  wire       I_src_clk,
    input  wire       I_src_rst_n,
    input  wire       I_src_toggle,
    input  wire [7:0] I_src_ascii,
    input  wire       I_src_bbox_valid,
    input  wire [10:0] I_src_x_min,
    input  wire [10:0] I_src_x_max,
    input  wire [9:0] I_src_y_min,
    input  wire [9:0] I_src_y_max,
    input  wire       I_dst_clk,
    input  wire       I_dst_rst_n,
    output reg        O_dst_toggle,
    output reg [7:0]  O_dst_ascii,
    output reg        O_dst_bbox_valid,
    output reg [10:0] O_dst_x_min,
    output reg [10:0] O_dst_x_max,
    output reg [9:0]  O_dst_y_min,
    output reg [9:0]  O_dst_y_max,
    output reg        O_dst_valid
);

    reg [50:0] src_payload_hold;
    reg       src_toggle_seen;
    reg       dst_toggle_sync1;
    reg       dst_toggle_sync2;
    reg       dst_toggle_seen;
    reg       dst_capture_pending;
    reg [50:0] dst_payload_sync1;
    reg [50:0] dst_payload_sync2;

    // 分类和坐标必须在相同toggle事件中锁存，避免框对应到另一帧类别。
    always @(posedge I_src_clk or negedge I_src_rst_n) begin
        if (!I_src_rst_n) begin
            src_payload_hold <= {1'b0, 42'd0, "?"};
            src_toggle_seen <= 1'b0;
        end
        else begin
            if (I_src_toggle != src_toggle_seen) begin
                src_payload_hold <= {
                    I_src_bbox_valid, I_src_x_min, I_src_x_max,
                    I_src_y_min, I_src_y_max, I_src_ascii
                };
                src_toggle_seen <= I_src_toggle;
            end
        end
    end

    always @(posedge I_dst_clk or negedge I_dst_rst_n) begin
        if (!I_dst_rst_n) begin
            dst_toggle_sync1 <= 1'b0;
            dst_toggle_sync2 <= 1'b0;
            dst_toggle_seen  <= 1'b0;
            dst_capture_pending <= 1'b0;
            dst_payload_sync1 <= {1'b0, 42'd0, "?"};
            dst_payload_sync2 <= {1'b0, 42'd0, "?"};
            O_dst_toggle     <= 1'b0;
            O_dst_ascii      <= "?";
            O_dst_bbox_valid <= 1'b0;
            O_dst_x_min      <= 11'd0;
            O_dst_x_max      <= 11'd0;
            O_dst_y_min      <= 10'd0;
            O_dst_y_max      <= 10'd0;
            O_dst_valid      <= 1'b0;
        end
        else begin
            dst_toggle_sync1 <= I_src_toggle;
            dst_toggle_sync2 <= dst_toggle_sync1;
            dst_payload_sync1 <= src_payload_hold;
            dst_payload_sync2 <= dst_payload_sync1;
            O_dst_valid      <= 1'b0;
            if (dst_capture_pending) begin
                // 再等待一个目标时钟，使稳定负载与同步后的toggle对齐。
                dst_capture_pending <= 1'b0;
                O_dst_toggle        <= dst_toggle_sync2;
                O_dst_bbox_valid    <= dst_payload_sync2[50];
                O_dst_x_min         <= dst_payload_sync2[49:39];
                O_dst_x_max         <= dst_payload_sync2[38:28];
                O_dst_y_min         <= dst_payload_sync2[27:18];
                O_dst_y_max         <= dst_payload_sync2[17:8];
                O_dst_ascii         <= dst_payload_sync2[7:0];
                O_dst_valid         <= 1'b1;
            end
            else if (dst_toggle_sync2 != dst_toggle_seen) begin
                dst_toggle_seen <= dst_toggle_sync2;
                dst_capture_pending <= 1'b1;
            end
        end
    end

endmodule
