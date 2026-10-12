`timescale 1ns/1ps
// Frame-based gray-world white balance for the four-pixel RGB888 stream.
// Keep the vendor line-delay path and its early frame marker: downstream
// DDR/video_in relies on that timing. Gains are constant within each frame.
module awb #(
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920
) (
    input             I_clk,
    input             I_rst_n,
    input             I_tlast,
    input             I_tuser,
    input      [95:0] I_tdata,
    input             I_tvalid,
    output            I_tready,
    output            O_tlast,
    output            O_tuser,
    output     [95:0] O_tdata,
    output            O_tvalid,
    input             O_tready
);

    // One of every 64 valid four-pixel words is metered. Reject very dark
    // and nearly clipped pixels; those are poor color references. In a
    // 1280x720 frame this gives at most 3600 samples, so 24-bit sums suffice.
    reg [5:0]  sample_phase;
    reg [12:0] sample_count;
    reg [23:0] sum_r;
    reg [23:0] sum_g;
    reg [23:0] sum_b;
    wire [7:0] meter_r = I_tdata[23:16];
    wire [7:0] meter_g = I_tdata[15:8];
    wire [7:0] meter_b = I_tdata[7:0];
    wire meter_ok = meter_r >= 8'd16 && meter_r <= 8'd239 &&
                    meter_g >= 8'd16 && meter_g <= 8'd239 &&
                    meter_b >= 8'd16 && meter_b <= 8'd239;

    // Q8 gains: 256 is unity, limits are 0.75x and 1.75x.
    // Compare weighted sums instead of running a divider for every pixel.
    reg [8:0] gain_r;
    reg [8:0] gain_b;
    wire [32:0] reference_level = {1'b0, sum_g, 8'b0};
    wire [32:0] red_level  = sum_r * gain_r;
    wire [32:0] blue_level = sum_b * gain_b;
    wire [32:0] deadband = reference_level >> 5; // 3.125%

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sample_phase <= 6'd0;
            sample_count <= 13'd0;
            sum_r <= 24'd0;
            sum_g <= 24'd0;
            sum_b <= 24'd0;
            gain_r <= 9'd256;
            gain_b <= 9'd256;
        end else if (I_tuser) begin
            // The old sums describe the completed frame. Change each gain
            // by at most 1/64 per frame to avoid flicker during AE changes.
            if (sample_count >= 13'd64) begin
                if (red_level + deadband < reference_level) begin
                    if (gain_r < 9'd448) gain_r <= gain_r + 9'd4;
                end else if (red_level > reference_level + deadband) begin
                    if (gain_r > 9'd192) gain_r <= gain_r - 9'd4;
                end
                if (blue_level + deadband < reference_level) begin
                    if (gain_b < 9'd448) gain_b <= gain_b + 9'd4;
                end else if (blue_level > reference_level + deadband) begin
                    if (gain_b > 9'd192) gain_b <= gain_b - 9'd4;
                end
            end
            sample_phase <= 6'd0;
            sample_count <= 13'd0;
            sum_r <= 24'd0;
            sum_g <= 24'd0;
            sum_b <= 24'd0;
        end else if (I_tvalid) begin
            sample_phase <= sample_phase + 6'd1;
            if (sample_phase == 6'd0 && meter_ok) begin
                sample_count <= sample_count + 13'd1;
                sum_r <= sum_r + {16'd0, meter_r};
                sum_g <= sum_g + {16'd0, meter_g};
                sum_b <= sum_b + {16'd0, meter_b};
            end
        end
    end

    // Preserve the reference design's two input registers and BRAM delay.
    reg [95:0] input_data_d0, input_data_d1;
    reg input_valid_d0, input_valid_d1;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            input_data_d0 <= 96'd0;
            input_data_d1 <= 96'd0;
            input_valid_d0 <= 1'b0;
            input_valid_d1 <= 1'b0;
        end else begin
            input_data_d0 <= I_tdata;
            input_data_d1 <= input_data_d0;
            input_valid_d0 <= I_tvalid;
            input_valid_d1 <= input_valid_d0;
        end
    end

    wire [95:0] delayed_data;
    wire delayed_valid;
    wire delayed_frame;
    signal_delay #(
        .IMG_HEIGHT(IMG_HEIGHT),
        .IMG_WIDTH(IMG_WIDTH),
        .DATA_WIDTH(96),
        .DELAY_CYCLE(50)
    ) u_signal_delay (
        .I_clk(I_clk),
        .I_rst_n(I_rst_n),
        .I_tuser(I_tuser),
        .I_valid(input_valid_d1),
        .I_data(input_data_d1),
        .O_valid(delayed_valid),
        .O_data(delayed_data),
        .O_tuser(delayed_frame)
    );

    reg [95:0] pixel_data;
    reg pixel_valid;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            pixel_data <= 96'd0;
            pixel_valid <= 1'b0;
        end else begin
            pixel_data <= delayed_data;
            pixel_valid <= delayed_valid;
        end
    end

    // Eight 8x9 multipliers replace the original per-pixel divider chain.
    // The green channel is the reference and passes through unchanged.
    reg [16:0] r_product0, r_product1, r_product2, r_product3;
    reg [16:0] b_product0, b_product1, b_product2, b_product3;
    reg [7:0] g_pixel0, g_pixel1, g_pixel2, g_pixel3;
    reg output_valid;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_product0 <= 17'd0; r_product1 <= 17'd0;
            r_product2 <= 17'd0; r_product3 <= 17'd0;
            b_product0 <= 17'd0; b_product1 <= 17'd0;
            b_product2 <= 17'd0; b_product3 <= 17'd0;
            g_pixel0 <= 8'd0; g_pixel1 <= 8'd0;
            g_pixel2 <= 8'd0; g_pixel3 <= 8'd0;
            output_valid <= 1'b0;
        end else begin
            output_valid <= pixel_valid;
            if (pixel_valid) begin
                r_product0 <= pixel_data[23:16] * gain_r;
                g_pixel0 <= pixel_data[15:8];
                b_product0 <= pixel_data[7:0] * gain_b;
                r_product1 <= pixel_data[47:40] * gain_r;
                g_pixel1 <= pixel_data[39:32];
                b_product1 <= pixel_data[31:24] * gain_b;
                r_product2 <= pixel_data[71:64] * gain_r;
                g_pixel2 <= pixel_data[63:56];
                b_product2 <= pixel_data[55:48] * gain_b;
                r_product3 <= pixel_data[95:88] * gain_r;
                g_pixel3 <= pixel_data[87:80];
                b_product3 <= pixel_data[79:72] * gain_b;
            end
        end
    end

    wire [7:0] r0 = r_product0[16] ? 8'hff : r_product0[15:8];
    wire [7:0] r1 = r_product1[16] ? 8'hff : r_product1[15:8];
    wire [7:0] r2 = r_product2[16] ? 8'hff : r_product2[15:8];
    wire [7:0] r3 = r_product3[16] ? 8'hff : r_product3[15:8];
    wire [7:0] b0 = b_product0[16] ? 8'hff : b_product0[15:8];
    wire [7:0] b1 = b_product1[16] ? 8'hff : b_product1[15:8];
    wire [7:0] b2 = b_product2[16] ? 8'hff : b_product2[15:8];
    wire [7:0] b3 = b_product3[16] ? 8'hff : b_product3[15:8];

    assign O_tdata = output_valid ?
        {r3,g_pixel3,b3, r2,g_pixel2,b2,
         r1,g_pixel1,b1, r0,g_pixel0,b0} : 96'd0;
    assign O_tvalid = output_valid;
    assign O_tlast = !pixel_valid && output_valid;
    assign O_tuser = I_tuser; // Early marker is required by the video FIFO.
    assign I_tready = O_tready;
endmodule
