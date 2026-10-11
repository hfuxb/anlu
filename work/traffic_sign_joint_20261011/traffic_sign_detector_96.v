`timescale 1ns / 1ps

// 低资源蓝底白箭头路牌识别器。每帧只维护四个蓝色候选框。
// 候选框须接近圆形且有足够蓝色覆盖；下一帧再匹配归一化4x4白色箭头分布。
// 在线按固定12像素横向间隙跟踪；帧尾按固定48像素间隙合并邻近蓝块，不缓存整帧。
module traffic_sign_detector_96 #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [95:0] I_tdata,
    output reg         O_busy,
    output reg         O_done,
    output reg         O_result_valid,
    output reg  [4:0]  O_result_class,
    output reg  [7:0]  O_result_ascii,
    output reg         O_bbox_valid,
    output reg  [10:0] O_x_min,
    output reg  [10:0] O_x_max,
    output reg  [9:0]  O_y_min,
    output reg  [9:0]  O_y_max,
    output reg         O_frame_drop
);

    localparam integer X_GROUP_BITS = (IMG_WIDTH / 4 > 1) ? $clog2(IMG_WIDTH / 4) : 1;
    localparam integer CANDIDATE_SLOTS = 4;
    localparam [11:0] SCAN_JOIN_GAP = 12'd12;
    localparam [11:0] CLUSTER_JOIN_GAP = 12'd48;
    localparam integer REPLACE_AREA = 64;
    localparam integer MIN_SIGN_SIZE = 24;
    localparam integer MAX_SIGN_SIZE = 512;
    localparam integer MIN_BLUE_AREA = 128;
    localparam integer MIN_WHITE_TOTAL = 24;
    localparam integer BOX_MARGIN = 4;

    localparam [4:0] CLASS_UNKNOWN = 5'd0;
    localparam [4:0] CLASS_LEFT    = 5'd1;
    localparam [4:0] CLASS_RIGHT   = 5'd2;
    localparam [4:0] CLASS_STRAIGHT= 5'd3;
    localparam [15:0] MASK_STRAIGHT = 16'h6666;
    localparam [15:0] MASK_LEFT     = 16'h4472;
    localparam [15:0] MASK_RIGHT    = 16'h22E4;

    // 四个候选槽代替全帧单一外接框；槽满时可替换面积不超过64像素的槽。
    reg [CANDIDATE_SLOTS-1:0] candidate_valid;
    reg [20:0] candidate_area [0:CANDIDATE_SLOTS-1];
    reg [10:0] candidate_x_min[0:CANDIDATE_SLOTS-1];
    reg [10:0] candidate_x_max[0:CANDIDATE_SLOTS-1];
    reg [9:0]  candidate_y_min[0:CANDIDATE_SLOTS-1];
    reg [9:0]  candidate_y_max[0:CANDIDATE_SLOTS-1];

    reg [CANDIDATE_SLOTS-1:0] candidate_valid_next;
    reg [20:0] candidate_area_next [0:CANDIDATE_SLOTS-1];
    reg [10:0] candidate_x_min_next[0:CANDIDATE_SLOTS-1];
    reg [10:0] candidate_x_max_next[0:CANDIDATE_SLOTS-1];
    reg [9:0]  candidate_y_min_next[0:CANDIDATE_SLOTS-1];
    reg [9:0]  candidate_y_max_next[0:CANDIDATE_SLOTS-1];

    reg [CANDIDATE_SLOTS-1:0] cluster_valid;
    reg [20:0] cluster_area [0:CANDIDATE_SLOTS-1];
    reg [10:0] cluster_x_min[0:CANDIDATE_SLOTS-1];
    reg [10:0] cluster_x_max[0:CANDIDATE_SLOTS-1];
    reg [9:0]  cluster_y_min[0:CANDIDATE_SLOTS-1];
    reg [9:0]  cluster_y_max[0:CANDIDATE_SLOTS-1];
    reg [CANDIDATE_SLOTS-1:0] cluster_next_valid;
    reg [20:0] cluster_next_area [0:CANDIDATE_SLOTS-1];
    reg [10:0] cluster_next_x_min[0:CANDIDATE_SLOTS-1];
    reg [10:0] cluster_next_x_max[0:CANDIDATE_SLOTS-1];
    reg [9:0]  cluster_next_y_min[0:CANDIDATE_SLOTS-1];
    reg [9:0]  cluster_next_y_max[0:CANDIDATE_SLOTS-1];

    // 当前帧识别上一帧筛出的框；框与最终分类一起进入结果级。
    reg        track_valid;
    reg [10:0] track_x_min;
    reg [10:0] track_x_max;
    reg [9:0]  track_y_min;
    reg [9:0]  track_y_max;
    // 帧尾后先登记候选合并框，再单独评分，切断串接的组合路径。
    reg        frame_select_pending;
    reg        cluster_select_pending;
    reg [14:0] white_cell_count[0:15];
    reg [11:0] white_total_count;

    reg [X_GROUP_BITS-1:0] x_group;
    reg [9:0] y_pos;

    // 输入和颜色级流水保持4像素/拍吞吐率。
    reg        pixel_stage_valid;
    reg        pixel_stage_tuser;
    reg        pixel_stage_tlast;
    reg [95:0] pixel_stage_data;

    reg        feature_stage_valid;
    reg        feature_stage_tuser;
    reg        feature_stage_tlast;
    reg [X_GROUP_BITS-1:0] feature_stage_x;
    reg [9:0]  feature_stage_y;
    reg [95:0] feature_stage_data;
    reg        feature_blue_valid;
    reg [2:0]  feature_blue_count;
    reg [10:0] feature_blue_x_min;
    reg [10:0] feature_blue_x_max;

    // 分类结果级保存同一候选的框、白色形状和有效标志。
    reg        result_stage_valid;
    reg        result_stage_track_valid;
    reg [10:0] result_stage_x_min;
    reg [10:0] result_stage_x_max;
    reg [9:0]  result_stage_y_min;
    reg [9:0]  result_stage_y_max;
    reg [15:0] result_stage_white_mask;
    reg [11:0] result_stage_white_total;
    // 强格保留原判定；弱格只参与头部和竖杆证据一致的转向补充判定。
    reg [15:0] result_stage_weak_mask;
    reg [22:0] result_stage_box_area;
    reg [11:0] result_stage_width;
    reg [11:0] result_stage_height;
    reg [15:0] result_head_left_count;
    reg [15:0] result_head_right_count;
    reg [15:0] result_stem_left_count;
    reg [15:0] result_stem_right_count;
    reg signed [16:0] result_head_difference;
    reg signed [16:0] result_stem_difference;
    reg [1:0] result_legacy_arrow;
    reg [1:0] result_turn_shape;
    reg result_head_left;
    reg result_head_right;
    reg result_stem_left;
    reg result_stem_right;
    reg result_candidate_matches;
    reg turn_score_pending;
    reg candidate_match_pending;
    reg result_commit_pending;

    wire [X_GROUP_BITS-1:0] active_x =
        pixel_stage_tuser ? {X_GROUP_BITS{1'b0}} : x_group;
    wire [9:0] active_y = pixel_stage_tuser ? 10'd0 : y_pos;
    wire [10:0] word_x_base = {active_x, 2'b00};
    wire [10:0] feature_word_x_base = {feature_stage_x, 2'b00};
    wire frame_end = feature_stage_valid && feature_stage_tlast &&
                     (feature_stage_y == IMG_HEIGHT - 1);

    function F_blue_pixel;
        input [23:0] pixel;
        integer red;
        integer green;
        integer blue;
        begin
            red   = pixel[23:16];
            green = pixel[15:8];
            blue  = pixel[7:0];
            F_blue_pixel = (blue >= 8'd70) && (blue > red + 20) &&
                           (blue > green + 10) && (green > red - 30);
        end
    endfunction

    // 只有同一候选的四条边都在框尺寸的1/24以内，才使用弱格补充证据。
    function F_edge_matches;
        input [11:0] old_edge;
        input [11:0] new_edge;
        input [11:0] size;
        reg [11:0] difference;
        reg [16:0] scaled_difference;
        begin
            difference = (old_edge >= new_edge) ? old_edge - new_edge : new_edge - old_edge;
            scaled_difference = ({5'd0, difference} << 4) + ({5'd0, difference} << 3);
            F_edge_matches = (scaled_difference <= {5'd0, size});
        end
    endfunction

    // 弱格不能单独识别方向；强格外白块和反方向优势仍必须受限。
    function [1:0] F_turn_shape;
        input [15:0] weak_mask;
        input [15:0] strong_mask;
        input [11:0] white_total;
        reg [4:0] left_hits;
        reg [4:0] right_hits;
        reg [4:0] left_extra;
        reg [4:0] right_extra;
        integer bit_index;
        begin
            left_hits = 0;
            right_hits = 0;
            left_extra = 0;
            right_extra = 0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                if (16'h6FF6 & (16'h0001 << bit_index)) begin
                    if (weak_mask[bit_index] && MASK_LEFT[bit_index]) left_hits = left_hits + 1'b1;
                    if (weak_mask[bit_index] && MASK_RIGHT[bit_index]) right_hits = right_hits + 1'b1;
                    if (strong_mask[bit_index] && !MASK_LEFT[bit_index]) left_extra = left_extra + 1'b1;
                    if (strong_mask[bit_index] && !MASK_RIGHT[bit_index]) right_extra = right_extra + 1'b1;
                end
            end
            if (white_total < MIN_WHITE_TOTAL)
                F_turn_shape = 2'd0;
            else if ((left_hits >= 5) && (left_extra <= 2) && (left_hits >= right_hits + 1))
                F_turn_shape = 2'd1;
            else if ((right_hits >= 5) && (right_extra <= 2) && (right_hits >= left_hits + 1))
                F_turn_shape = 2'd2;
            else
                F_turn_shape = 2'd0;
        end
    endfunction

    function F_white_pixel;
        input [23:0] pixel;
        integer red;
        integer green;
        integer blue;
        begin
            red   = pixel[23:16];
            green = pixel[15:8];
            blue  = pixel[7:0];
            F_white_pixel = (red >= 8'd150) && (green >= 8'd150) &&
                            (blue >= 8'd150) &&
                            ((red - green < 40) && (green - red < 40)) &&
                            ((red - blue < 40) && (blue - red < 40));
        end
    endfunction

    function [2:0] F_count4;
        input [3:0] bits;
        begin
            F_count4 = bits[0] + bits[1] + bits[2] + bits[3];
        end
    endfunction

    function [1:0] F_first_set;
        input [3:0] bits;
        begin
            if (bits[0]) F_first_set = 2'd0;
            else if (bits[1]) F_first_set = 2'd1;
            else if (bits[2]) F_first_set = 2'd2;
            else F_first_set = 2'd3;
        end
    endfunction

    function [1:0] F_last_set;
        input [3:0] bits;
        begin
            if (bits[3]) F_last_set = 2'd3;
            else if (bits[2]) F_last_set = 2'd2;
            else if (bits[1]) F_last_set = 2'd1;
            else F_last_set = 2'd0;
        end
    endfunction

    // 以候选宽高的四分点归一化坐标，不需要可变除法器。
    function [1:0] F_cell4;
        input [11:0] offset;
        input [11:0] size;
        reg [13:0] offset_times4;
        reg [13:0] size_times2;
        reg [13:0] size_times3;
        begin
            offset_times4 = {offset, 2'b00};
            size_times2 = {2'b00, size} << 1;
            size_times3 = {2'b00, size} + size_times2;
            if (offset_times4 >= size_times3)
                F_cell4 = 2'd3;
            else if (offset_times4 >= size_times2)
                F_cell4 = 2'd2;
            else if (offset_times4 >= {2'b00, size})
                F_cell4 = 2'd1;
            else
                F_cell4 = 2'd0;
        end
    endfunction

    // 左右转模板取自实物路牌图，旧模板要求八格命中，会拒绝六格宽的弯箭头。
    // 忽略圆牌外接框四角，并要求模板外白块少、方向模板有明显优势。
    function [1:0] F_classify_arrow;
        input [15:0] white_mask;
        input [11:0] white_total;
        reg [15:0] usable_mask;
        reg [4:0] straight_hits;
        reg [4:0] left_hits;
        reg [4:0] right_hits;
        reg [3:0] straight_extra;
        reg [3:0] left_extra;
        reg [3:0] right_extra;
        integer bit_index;
        begin
            usable_mask = white_mask & 16'h6FF6;
            straight_hits = 0;
            left_hits = 0;
            right_hits = 0;
            straight_extra = 0;
            left_extra = 0;
            right_extra = 0;
            for (bit_index = 0; bit_index < 16; bit_index = bit_index + 1) begin
                if (usable_mask[bit_index]) begin
                    if (MASK_STRAIGHT[bit_index]) straight_hits = straight_hits + 1'b1;
                    else straight_extra = straight_extra + 1'b1;
                    if (MASK_LEFT[bit_index]) left_hits = left_hits + 1'b1;
                    else left_extra = left_extra + 1'b1;
                    if (MASK_RIGHT[bit_index]) right_hits = right_hits + 1'b1;
                    else right_extra = right_extra + 1'b1;
                end
            end

            if (white_total < MIN_WHITE_TOTAL)
                F_classify_arrow = 2'd0;
            else if ((left_hits >= 5) && (left_extra <= 1) &&
                     (left_hits >= straight_hits) &&
                     (left_hits >= right_hits + 2))
                F_classify_arrow = 2'd1;
            else if ((right_hits >= 5) && (right_extra <= 1) &&
                     (right_hits >= straight_hits) &&
                     (right_hits >= left_hits + 2))
                F_classify_arrow = 2'd2;
            else if ((straight_hits >= 5) && (straight_extra <= 2) &&
                     (straight_hits >= left_hits) &&
                     (straight_hits >= right_hits))
                F_classify_arrow = 2'd3;
            else
                F_classify_arrow = 2'd0;
        end
    endfunction

    wire [3:0] blue_mask = {
        F_blue_pixel(pixel_stage_data[95:72]),
        F_blue_pixel(pixel_stage_data[71:48]),
        F_blue_pixel(pixel_stage_data[47:24]),
        F_blue_pixel(pixel_stage_data[23:0])
    };
    wire blue_word_valid = |blue_mask;
    wire [2:0] blue_word_count = F_count4(blue_mask);
    wire [10:0] blue_word_x_min = word_x_base + F_first_set(blue_mask);
    wire [10:0] blue_word_x_max = word_x_base + F_last_set(blue_mask);

    wire [CANDIDATE_SLOTS-1:0] candidate_match;
    genvar match_slot;
    generate
        for (match_slot = 0; match_slot < CANDIDATE_SLOTS; match_slot = match_slot + 1) begin : g_candidate_match
            wire [11:0] current_x_max_plus_gap =
                {1'b0, feature_blue_x_max} + SCAN_JOIN_GAP;
            wire [11:0] candidate_x_max_plus_gap =
                {1'b0, candidate_x_max[match_slot]} + SCAN_JOIN_GAP;
            wire [10:0] y_max_plus1 = {1'b0, candidate_y_max[match_slot]} + 11'd1;
            assign candidate_match[match_slot] =
                !feature_stage_tuser && candidate_valid[match_slot] && feature_blue_valid &&
                (feature_stage_y >= candidate_y_min[match_slot]) &&
                ({1'b0, feature_stage_y} <= y_max_plus1) &&
                (current_x_max_plus_gap >= {1'b0, candidate_x_min[match_slot]}) &&
                ({1'b0, feature_blue_x_min} <= candidate_x_max_plus_gap);
        end
    endgenerate

    integer candidate_i;
    integer match_index;
    integer free_index;
    integer weakest_index;
    integer write_index;
    reg match_found;
    reg free_found;
    reg weakest_found;
    reg [20:0] merged_area;
    reg [10:0] merged_x_min;
    reg [10:0] merged_x_max;
    reg [9:0] merged_y_min;
    reg [9:0] merged_y_max;

    // 候选框附近的蓝块合并到一个槽；固定横向间隙限制像素路径延迟。
    always @* begin
        candidate_valid_next = {CANDIDATE_SLOTS{1'b0}};
        match_found = 1'b0;
        match_index = 0;
        free_found = 1'b0;
        free_index = 0;
        weakest_found = 1'b0;
        weakest_index = 0;
        merged_area = feature_blue_count;
        merged_x_min = feature_blue_x_min;
        merged_x_max = feature_blue_x_max;
        merged_y_min = feature_stage_y;
        merged_y_max = feature_stage_y;
        write_index = -1;

        for (candidate_i = 0; candidate_i < CANDIDATE_SLOTS; candidate_i = candidate_i + 1) begin
            candidate_valid_next[candidate_i] =
                feature_stage_tuser ? 1'b0 : candidate_valid[candidate_i];
            candidate_area_next[candidate_i] =
                feature_stage_tuser ? 21'd0 : candidate_area[candidate_i];
            candidate_x_min_next[candidate_i] =
                feature_stage_tuser ? 11'd0 : candidate_x_min[candidate_i];
            candidate_x_max_next[candidate_i] =
                feature_stage_tuser ? 11'd0 : candidate_x_max[candidate_i];
            candidate_y_min_next[candidate_i] =
                feature_stage_tuser ? 10'd0 : candidate_y_min[candidate_i];
            candidate_y_max_next[candidate_i] =
                feature_stage_tuser ? 10'd0 : candidate_y_max[candidate_i];

            if (candidate_match[candidate_i] && !match_found) begin
                match_found = 1'b1;
                match_index = candidate_i;
            end
            if (!candidate_valid_next[candidate_i] && !free_found) begin
                free_found = 1'b1;
                free_index = candidate_i;
            end
            // 候选槽已满时，优先覆盖编号最大的微小蓝色噪点。
            if (candidate_valid_next[candidate_i] &&
                (candidate_area_next[candidate_i] <= REPLACE_AREA)) begin
                weakest_found = 1'b1;
                weakest_index = candidate_i;
            end
        end

        if (feature_blue_valid) begin
            if (match_found) begin
                // 每组蓝像素只更新首个匹配槽。其他重叠槽留到帧尾合并。
                merged_area = feature_blue_count + candidate_area[match_index];
                merged_x_min = (candidate_x_min[match_index] < feature_blue_x_min) ?
                               candidate_x_min[match_index] : feature_blue_x_min;
                merged_x_max = (candidate_x_max[match_index] > feature_blue_x_max) ?
                               candidate_x_max[match_index] : feature_blue_x_max;
                merged_y_min = (candidate_y_min[match_index] < feature_stage_y) ?
                               candidate_y_min[match_index] : feature_stage_y;
                merged_y_max = (candidate_y_max[match_index] > feature_stage_y) ?
                               candidate_y_max[match_index] : feature_stage_y;
                candidate_valid_next[match_index] = 1'b1;
                candidate_area_next[match_index] = merged_area;
                candidate_x_min_next[match_index] = merged_x_min;
                candidate_x_max_next[match_index] = merged_x_max;
                candidate_y_min_next[match_index] = merged_y_min;
                candidate_y_max_next[match_index] = merged_y_max;
            end
            else begin
                if (free_found)
                    write_index = free_index;
                else if (weakest_found)
                    write_index = weakest_index;
                if (write_index >= 0) begin
                    candidate_valid_next[write_index] = 1'b1;
                    candidate_area_next[write_index] = feature_blue_count;
                    candidate_x_min_next[write_index] = feature_blue_x_min;
                    candidate_x_max_next[write_index] = feature_blue_x_max;
                    candidate_y_min_next[write_index] = feature_stage_y;
                    candidate_y_max_next[write_index] = feature_stage_y;
                end
            end
        end
    end

    reg        winner_valid;
    reg [20:0] winner_score;
    reg [10:0] winner_x_min;
    reg [10:0] winner_x_max;
    reg [9:0]  winner_y_min;
    reg [9:0]  winner_y_max;
    integer cluster_i;
    integer cluster_j;
    reg        cluster_close_x;
    reg        cluster_close_y;
    reg [10:0] cluster_union_x_min;
    reg [10:0] cluster_union_x_max;
    reg [9:0]  cluster_union_y_min;
    reg [9:0]  cluster_union_y_max;
    integer selection_i;
    reg candidate_shape_valid;
    reg [11:0] candidate_width_check;
    reg [10:0] candidate_height_check;
    reg [22:0] candidate_box_area;
    reg [13:0] width_times2;
    reg [13:0] height_times2;
    reg [13:0] width_times3;
    reg [13:0] height_times3;
    reg [22:0] blue_area_extended;
    reg [23:0] blue_area_times5;
    reg [25:0] blue_area_times10;
    reg [25:0] box_area_times7;

    // 每个候选独立合并48像素内的邻框，避免六对候选串行合并。
    always @* begin
        cluster_next_valid = candidate_valid;
        cluster_close_x = 1'b0;
        cluster_close_y = 1'b0;
        cluster_union_x_min = 11'd0;
        cluster_union_x_max = 11'd0;
        cluster_union_y_min = 10'd0;
        cluster_union_y_max = 10'd0;
        for (cluster_i = 0; cluster_i < CANDIDATE_SLOTS; cluster_i = cluster_i + 1) begin
            cluster_next_area[cluster_i] = candidate_area[cluster_i];
            cluster_next_x_min[cluster_i] = candidate_x_min[cluster_i];
            cluster_next_x_max[cluster_i] = candidate_x_max[cluster_i];
            cluster_next_y_min[cluster_i] = candidate_y_min[cluster_i];
            cluster_next_y_max[cluster_i] = candidate_y_max[cluster_i];

            for (cluster_j = 0; cluster_j < CANDIDATE_SLOTS; cluster_j = cluster_j + 1) begin
                cluster_close_x =
                    ({1'b0, candidate_x_min[cluster_i]} <=
                     {1'b0, candidate_x_max[cluster_j]} + CLUSTER_JOIN_GAP) &&
                    ({1'b0, candidate_x_min[cluster_j]} <=
                     {1'b0, candidate_x_max[cluster_i]} + CLUSTER_JOIN_GAP);
                cluster_close_y =
                    ({1'b0, candidate_y_min[cluster_i]} <=
                     {1'b0, candidate_y_max[cluster_j]} + CLUSTER_JOIN_GAP) &&
                    ({1'b0, candidate_y_min[cluster_j]} <=
                     {1'b0, candidate_y_max[cluster_i]} + CLUSTER_JOIN_GAP);
                cluster_union_x_min = (cluster_next_x_min[cluster_i] < candidate_x_min[cluster_j]) ?
                                      cluster_next_x_min[cluster_i] : candidate_x_min[cluster_j];
                cluster_union_x_max = (cluster_next_x_max[cluster_i] > candidate_x_max[cluster_j]) ?
                                      cluster_next_x_max[cluster_i] : candidate_x_max[cluster_j];
                cluster_union_y_min = (cluster_next_y_min[cluster_i] < candidate_y_min[cluster_j]) ?
                                      cluster_next_y_min[cluster_i] : candidate_y_min[cluster_j];
                cluster_union_y_max = (cluster_next_y_max[cluster_i] > candidate_y_max[cluster_j]) ?
                                      cluster_next_y_max[cluster_i] : candidate_y_max[cluster_j];
                if ((cluster_i != cluster_j) && candidate_valid[cluster_i] &&
                    candidate_valid[cluster_j] && cluster_close_x && cluster_close_y) begin
                    cluster_next_area[cluster_i] =
                        cluster_next_area[cluster_i] + candidate_area[cluster_j];
                    cluster_next_x_min[cluster_i] = cluster_union_x_min;
                    cluster_next_x_max[cluster_i] = cluster_union_x_max;
                    cluster_next_y_min[cluster_i] = cluster_union_y_min;
                    cluster_next_y_max[cluster_i] = cluster_union_y_max;
                end
            end
        end
    end

    // 最大蓝色面积优先；尺寸、近圆比例、蓝色覆盖率和箭头模板共同拒绝误检。
    always @* begin
        winner_valid = 1'b0;
        winner_score = 21'd0;
        winner_x_min = 11'd0;
        winner_x_max = 11'd0;
        winner_y_min = 10'd0;
        winner_y_max = 10'd0;
        candidate_shape_valid = 1'b0;
        candidate_width_check = 12'd0;
        candidate_height_check = 11'd0;
        candidate_box_area = 23'd0;
        width_times2 = 14'd0;
        height_times2 = 14'd0;
        width_times3 = 14'd0;
        height_times3 = 14'd0;
        blue_area_extended = 23'd0;
        blue_area_times5 = 24'd0;
        blue_area_times10 = 26'd0;
        box_area_times7 = 26'd0;
        for (selection_i = 0; selection_i < CANDIDATE_SLOTS;
             selection_i = selection_i + 1) begin
            candidate_width_check = {1'b0, cluster_x_max[selection_i]} -
                                    {1'b0, cluster_x_min[selection_i]} + 12'd1;
            candidate_height_check = {1'b0, cluster_y_max[selection_i]} -
                                     {1'b0, cluster_y_min[selection_i]} + 11'd1;
            candidate_box_area =
                {11'd0, candidate_width_check} * {12'd0, candidate_height_check};
            width_times2 = {2'b00, candidate_width_check} << 1;
            height_times2 = {3'b000, candidate_height_check} << 1;
            width_times3 = {2'b00, candidate_width_check} +
                           ({2'b00, candidate_width_check} << 1);
            height_times3 = {3'b000, candidate_height_check} +
                            ({3'b000, candidate_height_check} << 1);
            blue_area_extended = {2'b00, cluster_area[selection_i]};
            blue_area_times5 = {1'b0, blue_area_extended} +
                               ({1'b0, blue_area_extended} << 2);
            blue_area_times10 = ({5'd0, cluster_area[selection_i]} << 3) +
                                ({5'd0, cluster_area[selection_i]} << 1);
            box_area_times7 = ({3'd0, candidate_box_area} << 2) +
                              ({3'd0, candidate_box_area} << 1) +
                              {3'd0, candidate_box_area};

            candidate_shape_valid = cluster_valid[selection_i] &&
                (cluster_area[selection_i] >= MIN_BLUE_AREA) &&
                (candidate_width_check >= MIN_SIGN_SIZE) &&
                (candidate_height_check >= MIN_SIGN_SIZE) &&
                (candidate_width_check <= MAX_SIGN_SIZE) &&
                (candidate_height_check <= MAX_SIGN_SIZE) &&
                (width_times2 <= height_times3) &&
                (height_times2 <= width_times3) &&
                (blue_area_times5 >= candidate_box_area) &&
                (blue_area_times10 <= box_area_times7);
            if (candidate_shape_valid &&
                (!winner_valid || (cluster_area[selection_i] > winner_score))) begin
                winner_valid = 1'b1;
                winner_score = cluster_area[selection_i];
                winner_x_min = cluster_x_min[selection_i];
                winner_x_max = cluster_x_max[selection_i];
                winner_y_min = cluster_y_min[selection_i];
                winner_y_max = cluster_y_max[selection_i];
            end
        end
    end

    // ROI白像素按框宽高分到4x4格；格内至少20%白色才算命中，抑制边界漏入。
    wire [11:0] track_width =
        {1'b0, track_x_max} - {1'b0, track_x_min} + 12'd1;
    wire [11:0] track_height =
        {2'b00, track_y_max} - {2'b00, track_y_min} + 12'd1;
    wire [22:0] track_box_area =
        {11'd0, track_width} * {11'd0, track_height};
    wire [11:0] pixel_x0 = {1'b0, feature_word_x_base};
    wire [11:0] pixel_x1 = pixel_x0 + 12'd1;
    wire [11:0] pixel_x2 = pixel_x0 + 12'd2;
    wire [11:0] pixel_x3 = pixel_x0 + 12'd3;
    wire [11:0] x_offset0 = pixel_x0 - {1'b0, track_x_min};
    wire [11:0] x_offset1 = pixel_x1 - {1'b0, track_x_min};
    wire [11:0] x_offset2 = pixel_x2 - {1'b0, track_x_min};
    wire [11:0] x_offset3 = pixel_x3 - {1'b0, track_x_min};
    wire [11:0] y_offset = {2'b00, feature_stage_y} - {2'b00, track_y_min};
    wire [1:0] roi_cell_x0 = F_cell4(x_offset0, track_width);
    wire [1:0] roi_cell_x1 = F_cell4(x_offset1, track_width);
    wire [1:0] roi_cell_x2 = F_cell4(x_offset2, track_width);
    wire [1:0] roi_cell_x3 = F_cell4(x_offset3, track_width);
    wire [1:0] roi_cell_y = F_cell4(y_offset, track_height);
    wire [3:0] white_roi_mask = {
        feature_stage_valid && track_valid &&
            (feature_stage_y >= track_y_min) && (feature_stage_y <= track_y_max) &&
            (pixel_x3 >= {1'b0, track_x_min}) && (pixel_x3 <= {1'b0, track_x_max}) &&
            F_white_pixel(feature_stage_data[95:72]),
        feature_stage_valid && track_valid &&
            (feature_stage_y >= track_y_min) && (feature_stage_y <= track_y_max) &&
            (pixel_x2 >= {1'b0, track_x_min}) && (pixel_x2 <= {1'b0, track_x_max}) &&
            F_white_pixel(feature_stage_data[71:48]),
        feature_stage_valid && track_valid &&
            (feature_stage_y >= track_y_min) && (feature_stage_y <= track_y_max) &&
            (pixel_x1 >= {1'b0, track_x_min}) && (pixel_x1 <= {1'b0, track_x_max}) &&
            F_white_pixel(feature_stage_data[47:24]),
        feature_stage_valid && track_valid &&
            (feature_stage_y >= track_y_min) && (feature_stage_y <= track_y_max) &&
            (pixel_x0 >= {1'b0, track_x_min}) && (pixel_x0 <= {1'b0, track_x_max}) &&
            F_white_pixel(feature_stage_data[23:0])
    };
    wire [3:0] white_index0 = {roi_cell_y, roi_cell_x0};
    wire [3:0] white_index1 = {roi_cell_y, roi_cell_x1};
    wire [3:0] white_index2 = {roi_cell_y, roi_cell_x2};
    wire [3:0] white_index3 = {roi_cell_y, roi_cell_x3};

    reg [2:0] white_grid_add[0:15];
    reg [14:0] white_cell_after[0:15];
    reg [15:0] white_cell_mask_after;
    reg [15:0] white_cell_weak_mask_after;
    reg [16:0] white_cell_sum;
    reg [22:0] white_cell_scaled;
    integer grid_i;
    always @* begin
        white_cell_mask_after = 16'd0;
        white_cell_weak_mask_after = 16'd0;
        white_cell_sum = 17'd0;
        white_cell_scaled = 23'd0;
        for (grid_i = 0; grid_i < 16; grid_i = grid_i + 1) begin
            white_grid_add[grid_i] = 3'd0;
            if (white_roi_mask[0] && (white_index0 == grid_i))
                white_grid_add[grid_i] = white_grid_add[grid_i] + 1'b1;
            if (white_roi_mask[1] && (white_index1 == grid_i))
                white_grid_add[grid_i] = white_grid_add[grid_i] + 1'b1;
            if (white_roi_mask[2] && (white_index2 == grid_i))
                white_grid_add[grid_i] = white_grid_add[grid_i] + 1'b1;
            if (white_roi_mask[3] && (white_index3 == grid_i))
                white_grid_add[grid_i] = white_grid_add[grid_i] + 1'b1;
            white_cell_sum = (feature_stage_tuser ? 17'd0 :
                              {2'b00, white_cell_count[grid_i]}) +
                             white_grid_add[grid_i];
            if (white_cell_sum >= 17'd32767)
                white_cell_after[grid_i] = 15'h7fff;
            else
                white_cell_after[grid_i] = white_cell_sum[14:0];
            white_cell_scaled =
                ({8'd0, white_cell_after[grid_i]} << 6) +
                ({8'd0, white_cell_after[grid_i]} << 4);
            white_cell_mask_after[grid_i] =
                (white_cell_scaled >= track_box_area);
            white_cell_weak_mask_after[grid_i] =
                ({white_cell_scaled, 1'b0} >= {1'b0, track_box_area});
        end
    end

    wire [11:0] white_total_base =
        feature_stage_tuser ? 12'd0 : white_total_count;
    wire [12:0] white_total_sum =
        {1'b0, white_total_base} + F_count4(white_roi_mask);
    wire [11:0] white_total_after =
        (white_total_sum >= 13'd4095) ? 12'd4095 : white_total_sum[11:0];
    // 先扩展符号位再乘160；差值范围为-65534至65534，25位不会溢出。
    wire signed [24:0] head_difference_extended =
        {{8{result_head_difference[16]}}, result_head_difference};
    wire signed [24:0] stem_difference_extended =
        {{8{result_stem_difference[16]}}, result_stem_difference};
    wire signed [24:0] head_difference_scaled =
        (head_difference_extended <<< 7) + (head_difference_extended <<< 5);
    wire signed [24:0] stem_difference_scaled =
        (stem_difference_extended <<< 7) + (stem_difference_extended <<< 5);
    wire signed [24:0] result_area_signed = $signed({2'b00, result_stage_box_area});
    wire [1:0] classified_arrow =
        (result_candidate_matches && result_turn_shape == 2'd1 && result_head_left && result_stem_left) ? 2'd1 :
        (result_candidate_matches && result_turn_shape == 2'd2 && result_head_right && result_stem_right) ? 2'd2 :
        result_legacy_arrow;
    wire [11:0] result_x_max_margin =
        {1'b0, result_stage_x_max} + BOX_MARGIN;
    wire [10:0] result_x_max_display =
        (result_x_max_margin >= IMG_WIDTH) ? IMG_WIDTH - 1 : result_x_max_margin[10:0];
    wire [10:0] result_y_max_margin =
        {1'b0, result_stage_y_max} + BOX_MARGIN;
    wire [9:0] result_y_max_display =
        (result_y_max_margin >= IMG_HEIGHT) ? IMG_HEIGHT - 1 : result_y_max_margin[9:0];

    integer reset_i;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            candidate_valid <= {CANDIDATE_SLOTS{1'b0}};
            cluster_valid <= {CANDIDATE_SLOTS{1'b0}};
            for (reset_i = 0; reset_i < CANDIDATE_SLOTS; reset_i = reset_i + 1) begin
                candidate_area[reset_i] <= 21'd0;
                candidate_x_min[reset_i] <= 11'd0;
                candidate_x_max[reset_i] <= 11'd0;
                candidate_y_min[reset_i] <= 10'd0;
                candidate_y_max[reset_i] <= 10'd0;
                cluster_area[reset_i] <= 21'd0;
                cluster_x_min[reset_i] <= 11'd0;
                cluster_x_max[reset_i] <= 11'd0;
                cluster_y_min[reset_i] <= 10'd0;
                cluster_y_max[reset_i] <= 10'd0;
            end
            track_valid <= 1'b0;
            track_x_min <= 11'd0;
            track_x_max <= 11'd0;
            track_y_min <= 10'd0;
            track_y_max <= 10'd0;
            frame_select_pending <= 1'b0;
            cluster_select_pending <= 1'b0;
            for (reset_i = 0; reset_i < 16; reset_i = reset_i + 1)
                white_cell_count[reset_i] <= 15'd0;
            white_total_count <= 12'd0;
            x_group <= {X_GROUP_BITS{1'b0}};
            y_pos <= 10'd0;
            pixel_stage_valid <= 1'b0;
            pixel_stage_tuser <= 1'b0;
            pixel_stage_tlast <= 1'b0;
            pixel_stage_data <= 96'd0;
            feature_stage_valid <= 1'b0;
            feature_stage_tuser <= 1'b0;
            feature_stage_tlast <= 1'b0;
            feature_stage_x <= {X_GROUP_BITS{1'b0}};
            feature_stage_y <= 10'd0;
            feature_stage_data <= 96'd0;
            feature_blue_valid <= 1'b0;
            feature_blue_count <= 3'd0;
            feature_blue_x_min <= 11'd0;
            feature_blue_x_max <= 11'd0;
            result_stage_valid <= 1'b0;
            result_stage_track_valid <= 1'b0;
            result_stage_x_min <= 11'd0;
            result_stage_x_max <= 11'd0;
            result_stage_y_min <= 10'd0;
            result_stage_y_max <= 10'd0;
            result_stage_white_mask <= 16'd0;
            result_stage_white_total <= 12'd0;
            result_stage_weak_mask <= 16'd0;
            result_stage_box_area <= 23'd0;
            result_stage_width <= 12'd0;
            result_stage_height <= 12'd0;
            result_head_left_count <= 16'd0;
            result_head_right_count <= 16'd0;
            result_stem_left_count <= 16'd0;
            result_stem_right_count <= 16'd0;
            result_head_difference <= 17'sd0;
            result_stem_difference <= 17'sd0;
            result_legacy_arrow <= 2'd0;
            result_turn_shape <= 2'd0;
            result_head_left <= 1'b0;
            result_head_right <= 1'b0;
            result_stem_left <= 1'b0;
            result_stem_right <= 1'b0;
            result_candidate_matches <= 1'b0;
            turn_score_pending <= 1'b0;
            candidate_match_pending <= 1'b0;
            result_commit_pending <= 1'b0;
            O_busy <= 1'b0;
            O_done <= 1'b0;
            O_result_valid <= 1'b0;
            O_result_class <= CLASS_UNKNOWN;
            O_result_ascii <= "?";
            O_bbox_valid <= 1'b0;
            O_x_min <= 11'd0;
            O_x_max <= 11'd0;
            O_y_min <= 10'd0;
            O_y_max <= 10'd0;
            O_frame_drop <= 1'b0;
        end
        else begin
            O_done <= 1'b0;
            O_result_valid <= 1'b0;
            O_frame_drop <= 1'b0;
            result_stage_valid <= 1'b0;
            turn_score_pending <= result_stage_valid;
            candidate_match_pending <= turn_score_pending;
            result_commit_pending <= candidate_match_pending;
            frame_select_pending <= frame_end;
            cluster_select_pending <= frame_select_pending;

            pixel_stage_valid <= I_tvalid;
            pixel_stage_tuser <= I_tvalid && I_tuser;
            pixel_stage_tlast <= I_tvalid && I_tlast;
            if (I_tvalid)
                pixel_stage_data <= I_tdata;

            feature_stage_valid <= pixel_stage_valid;
            feature_stage_tuser <= pixel_stage_valid && pixel_stage_tuser;
            feature_stage_tlast <= pixel_stage_valid && pixel_stage_tlast;
            feature_stage_x <= active_x;
            feature_stage_y <= active_y;
            feature_stage_data <= pixel_stage_data;
            feature_blue_valid <= blue_word_valid;
            feature_blue_count <= blue_word_count;
            feature_blue_x_min <= blue_word_x_min;
            feature_blue_x_max <= blue_word_x_max;

            if (pixel_stage_valid) begin
                if (pixel_stage_tlast) begin
                    x_group <= {X_GROUP_BITS{1'b0}};
                    y_pos <= (active_y == IMG_HEIGHT - 1) ? 10'd0 : active_y + 10'd1;
                end
                else begin
                    x_group <= active_x + 1'b1;
                end
            end

            if (feature_stage_valid) begin
                candidate_valid <= candidate_valid_next;
                for (reset_i = 0; reset_i < CANDIDATE_SLOTS; reset_i = reset_i + 1) begin
                    candidate_area[reset_i] <= candidate_area_next[reset_i];
                    candidate_x_min[reset_i] <= candidate_x_min_next[reset_i];
                    candidate_x_max[reset_i] <= candidate_x_max_next[reset_i];
                    candidate_y_min[reset_i] <= candidate_y_min_next[reset_i];
                    candidate_y_max[reset_i] <= candidate_y_max_next[reset_i];
                end

                for (reset_i = 0; reset_i < 16; reset_i = reset_i + 1)
                    white_cell_count[reset_i] <= frame_end ? 15'd0 : white_cell_after[reset_i];
                white_total_count <= frame_end ? 12'd0 : white_total_after;

                if (feature_stage_tuser)
                    O_busy <= 1'b1;

                if (frame_end) begin
                    O_busy <= 1'b0;
                    result_stage_valid <= 1'b1;
                    result_stage_track_valid <= track_valid;
                    result_stage_x_min <= track_x_min;
                    result_stage_x_max <= track_x_max;
                    result_stage_y_min <= track_y_min;
                    result_stage_y_max <= track_y_max;
                    result_stage_white_mask <= white_cell_mask_after;
                    result_stage_white_total <= white_total_after;
                    result_stage_weak_mask <= white_cell_weak_mask_after;
                    result_stage_box_area <= track_box_area;
                    result_stage_width <= track_width;
                    result_stage_height <= track_height;
                    result_head_left_count <= {1'b0, white_cell_after[1]} + {1'b0, white_cell_after[4]};
                    result_head_right_count <= {1'b0, white_cell_after[2]} + {1'b0, white_cell_after[7]};
                    result_stem_left_count <= {1'b0, white_cell_after[9]} + {1'b0, white_cell_after[13]};
                    result_stem_right_count <= {1'b0, white_cell_after[10]} + {1'b0, white_cell_after[14]};

                end
            end

            // 先锁存合并框，再用锁存框评分，两个阶段各用一拍。
            if (frame_select_pending) begin
                cluster_valid <= cluster_next_valid;
                for (reset_i = 0; reset_i < CANDIDATE_SLOTS; reset_i = reset_i + 1) begin
                    cluster_area[reset_i] <= cluster_next_area[reset_i];
                    cluster_x_min[reset_i] <= cluster_next_x_min[reset_i];
                    cluster_x_max[reset_i] <= cluster_next_x_max[reset_i];
                    cluster_y_min[reset_i] <= cluster_next_y_min[reset_i];
                    cluster_y_max[reset_i] <= cluster_next_y_max[reset_i];
                end
            end

            if (cluster_select_pending) begin
                if (winner_valid) begin
                    track_valid <= 1'b1;
                    track_x_min <= winner_x_min;
                    track_x_max <= winner_x_max;
                    track_y_min <= winner_y_min;
                    track_y_max <= winner_y_max;
                end
                else begin
                    track_valid <= 1'b0;
                    track_x_min <= 11'd0;
                    track_x_max <= 11'd0;
                    track_y_min <= 10'd0;
                    track_y_max <= 10'd0;
                end
            end

            if (result_stage_valid) begin
                result_head_difference <= $signed({1'b0, result_head_left_count}) -
                                          $signed({1'b0, result_head_right_count});
                result_stem_difference <= $signed({1'b0, result_stem_right_count}) -
                                          $signed({1'b0, result_stem_left_count});
                result_legacy_arrow <= F_classify_arrow(result_stage_white_mask, result_stage_white_total);
                result_turn_shape <= F_turn_shape(result_stage_weak_mask, result_stage_white_mask,
                                                 result_stage_white_total);
            end

            if (turn_score_pending) begin
                result_head_left <= head_difference_scaled > result_area_signed;
                result_head_right <= head_difference_scaled < -result_area_signed;
                result_stem_left <= stem_difference_scaled > result_area_signed;
                result_stem_right <= stem_difference_scaled < -result_area_signed;
            end

            // 候选评分先进入track寄存器，再关联取样框，避免评分与边差比较串接。
            if (candidate_match_pending) begin
                result_candidate_matches <= result_stage_track_valid && track_valid &&
                    F_edge_matches({1'b0, result_stage_x_min}, {1'b0, track_x_min}, result_stage_width) &&
                    F_edge_matches({1'b0, result_stage_x_max}, {1'b0, track_x_max}, result_stage_width) &&
                    F_edge_matches({2'b00, result_stage_y_min}, {2'b00, track_y_min}, result_stage_height) &&
                    F_edge_matches({2'b00, result_stage_y_max}, {2'b00, track_y_max}, result_stage_height);
            end

            if (result_commit_pending) begin
                O_done <= 1'b1;
                O_result_valid <= 1'b1;
                case (result_stage_track_valid ? classified_arrow : 2'd0)
                    2'd1: begin
                        O_result_class <= CLASS_LEFT;
                        O_result_ascii <= "L";
                        O_bbox_valid <= 1'b1;
                        // 四像素余量补回白箭头从蓝色外接框边缘造成的内缩。
                        O_x_min <= (result_stage_x_min >= BOX_MARGIN) ?
                                   result_stage_x_min - BOX_MARGIN : 11'd0;
                        O_x_max <= result_x_max_display;
                        O_y_min <= (result_stage_y_min >= BOX_MARGIN) ?
                                   result_stage_y_min - BOX_MARGIN : 10'd0;
                        O_y_max <= result_y_max_display;
                    end
                    2'd2: begin
                        O_result_class <= CLASS_RIGHT;
                        O_result_ascii <= "R";
                        O_bbox_valid <= 1'b1;
                        O_x_min <= (result_stage_x_min >= BOX_MARGIN) ?
                                   result_stage_x_min - BOX_MARGIN : 11'd0;
                        O_x_max <= result_x_max_display;
                        O_y_min <= (result_stage_y_min >= BOX_MARGIN) ?
                                   result_stage_y_min - BOX_MARGIN : 10'd0;
                        O_y_max <= result_y_max_display;
                    end
                    2'd3: begin
                        O_result_class <= CLASS_STRAIGHT;
                        O_result_ascii <= "S";
                        O_bbox_valid <= 1'b1;
                        O_x_min <= (result_stage_x_min >= BOX_MARGIN) ?
                                   result_stage_x_min - BOX_MARGIN : 11'd0;
                        O_x_max <= result_x_max_display;
                        O_y_min <= (result_stage_y_min >= BOX_MARGIN) ?
                                   result_stage_y_min - BOX_MARGIN : 10'd0;
                        O_y_max <= result_y_max_display;
                    end
                    default: begin
                        O_result_class <= CLASS_UNKNOWN;
                        O_result_ascii <= "?";
                        O_bbox_valid <= 1'b0;
                        O_x_min <= 11'd0;
                        O_x_max <= 11'd0;
                        O_y_min <= 10'd0;
                        O_y_max <= 10'd0;
                    end
                endcase
            end
        end
    end

endmodule
