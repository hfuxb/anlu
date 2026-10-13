// Every Latin letter, decimal digit and punctuation uses the same 16x16 cell.
// A 5x7 glyph is doubled to 10x14, centered at columns 3..12 / rows 1..14.
// Chinese glyphs retain their original 16x16 bitmaps.
module osd_char_lib (
    input wire [7:0] I_char,
    input wire [3:0] I_row,
    output reg [15:0] O_row_bits
);
    localparam CHAR_AN=8'h80, CHAR_LU=8'h81;
    always @(*) begin
        case(I_char)
            CHAR_AN: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h0200;
                    4'd1: O_row_bits = 16'h7ff0;
                    4'd2: O_row_bits = 16'h4410;
                    4'd3: O_row_bits = 16'h0400;
                    4'd4: O_row_bits = 16'h7ff0;
                    4'd5: O_row_bits = 16'h0840;
                    4'd6: O_row_bits = 16'h1040;
                    4'd7: O_row_bits = 16'h1c80;
                    4'd8: O_row_bits = 16'h0300;
                    4'd9: O_row_bits = 16'h0cc0;
                    4'd10: O_row_bits = 16'h7020;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            CHAR_LU: begin
                case(I_row)
                    4'd0: O_row_bits = 16'h79e0;
                    4'd1: O_row_bits = 16'h4a20;
                    4'd2: O_row_bits = 16'h4d40;
                    4'd3: O_row_bits = 16'h7880;
                    4'd4: O_row_bits = 16'h1140;
                    4'd5: O_row_bits = 16'h1630;
                    4'd6: O_row_bits = 16'h5be0;
                    4'd7: O_row_bits = 16'h5220;
                    4'd8: O_row_bits = 16'h5220;
                    4'd9: O_row_bits = 16'h5be0;
                    4'd10: O_row_bits = 16'h6220;
                    4'd11: O_row_bits = 16'h0000;
                    4'd12: O_row_bits = 16'h0000;
                    4'd13: O_row_bits = 16'h0000;
                    4'd14: O_row_bits = 16'h0000;
                    4'd15: O_row_bits = 16'h0000;
                    default: O_row_bits = 16'h0000;
                endcase
            end
            8'h41: begin // A
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1ff8;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h42: begin // B
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1fe0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1fe0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h43: begin // C
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07f8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1800;
                    4'd9,4'd10: O_row_bits=16'h1800;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h07f8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h44: begin // D
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1fe0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1818;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1fe0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h45: begin // E
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1800;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h1ff8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h46: begin // F
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1800;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h1800;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h47: begin // G
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07f8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h19f8;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07f8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h48: begin // H
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1ff8;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h49: begin // I
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h0180;
                    4'd5,4'd6: O_row_bits=16'h0180;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0180;
                    4'd13,4'd14: O_row_bits=16'h1ff8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4a: begin // J
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h01f8;
                    4'd3,4'd4: O_row_bits=16'h0060;
                    4'd5,4'd6: O_row_bits=16'h0060;
                    4'd7,4'd8: O_row_bits=16'h0060;
                    4'd9,4'd10: O_row_bits=16'h0060;
                    4'd11,4'd12: O_row_bits=16'h1860;
                    4'd13,4'd14: O_row_bits=16'h0780;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4b: begin // K
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1860;
                    4'd5,4'd6: O_row_bits=16'h1980;
                    4'd7,4'd8: O_row_bits=16'h1e00;
                    4'd9,4'd10: O_row_bits=16'h1980;
                    4'd11,4'd12: O_row_bits=16'h1860;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4c: begin // L
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1800;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1800;
                    4'd9,4'd10: O_row_bits=16'h1800;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h1ff8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4d: begin // M
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1e78;
                    4'd5,4'd6: O_row_bits=16'h1998;
                    4'd7,4'd8: O_row_bits=16'h1998;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4e: begin // N
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1e18;
                    4'd5,4'd6: O_row_bits=16'h1e18;
                    4'd7,4'd8: O_row_bits=16'h1998;
                    4'd9,4'd10: O_row_bits=16'h1878;
                    4'd11,4'd12: O_row_bits=16'h1878;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h4f: begin // O
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1818;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h50: begin // P
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1fe0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1800;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h1800;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h51: begin // Q
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1818;
                    4'd9,4'd10: O_row_bits=16'h1998;
                    4'd11,4'd12: O_row_bits=16'h1860;
                    4'd13,4'd14: O_row_bits=16'h0798;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h52: begin // R
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1fe0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1980;
                    4'd11,4'd12: O_row_bits=16'h1860;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h53: begin // S
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07f8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h07e0;
                    4'd9,4'd10: O_row_bits=16'h0018;
                    4'd11,4'd12: O_row_bits=16'h0018;
                    4'd13,4'd14: O_row_bits=16'h1fe0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h54: begin // T
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h0180;
                    4'd5,4'd6: O_row_bits=16'h0180;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0180;
                    4'd13,4'd14: O_row_bits=16'h0180;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h55: begin // U
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1818;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h56: begin // V
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1818;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h0660;
                    4'd13,4'd14: O_row_bits=16'h0180;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h57: begin // W
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h1998;
                    4'd9,4'd10: O_row_bits=16'h1998;
                    4'd11,4'd12: O_row_bits=16'h1e78;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h58: begin // X
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h0660;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0660;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h1818;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h59: begin // Y
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1818;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h0660;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0180;
                    4'd13,4'd14: O_row_bits=16'h0180;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h5a: begin // Z
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h0018;
                    4'd5,4'd6: O_row_bits=16'h0060;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0600;
                    4'd11,4'd12: O_row_bits=16'h1800;
                    4'd13,4'd14: O_row_bits=16'h1ff8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h30: begin // 0
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1878;
                    4'd7,4'd8: O_row_bits=16'h1998;
                    4'd9,4'd10: O_row_bits=16'h1e18;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h31: begin // 1
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h0180;
                    4'd3,4'd4: O_row_bits=16'h0780;
                    4'd5,4'd6: O_row_bits=16'h0180;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0180;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h32: begin // 2
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h0018;
                    4'd7,4'd8: O_row_bits=16'h0060;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0600;
                    4'd13,4'd14: O_row_bits=16'h1ff8;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h33: begin // 3
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1fe0;
                    4'd3,4'd4: O_row_bits=16'h0018;
                    4'd5,4'd6: O_row_bits=16'h0018;
                    4'd7,4'd8: O_row_bits=16'h07e0;
                    4'd9,4'd10: O_row_bits=16'h0018;
                    4'd11,4'd12: O_row_bits=16'h0018;
                    4'd13,4'd14: O_row_bits=16'h1fe0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h34: begin // 4
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h0060;
                    4'd3,4'd4: O_row_bits=16'h01e0;
                    4'd5,4'd6: O_row_bits=16'h0660;
                    4'd7,4'd8: O_row_bits=16'h1860;
                    4'd9,4'd10: O_row_bits=16'h1ff8;
                    4'd11,4'd12: O_row_bits=16'h0060;
                    4'd13,4'd14: O_row_bits=16'h0060;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h35: begin // 5
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h0018;
                    4'd11,4'd12: O_row_bits=16'h0018;
                    4'd13,4'd14: O_row_bits=16'h1fe0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h36: begin // 6
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1800;
                    4'd5,4'd6: O_row_bits=16'h1800;
                    4'd7,4'd8: O_row_bits=16'h1fe0;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h37: begin // 7
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h1ff8;
                    4'd3,4'd4: O_row_bits=16'h0018;
                    4'd5,4'd6: O_row_bits=16'h0060;
                    4'd7,4'd8: O_row_bits=16'h0180;
                    4'd9,4'd10: O_row_bits=16'h0600;
                    4'd11,4'd12: O_row_bits=16'h0600;
                    4'd13,4'd14: O_row_bits=16'h0600;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h38: begin // 8
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h07e0;
                    4'd9,4'd10: O_row_bits=16'h1818;
                    4'd11,4'd12: O_row_bits=16'h1818;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h39: begin // 9
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h1818;
                    4'd7,4'd8: O_row_bits=16'h07f8;
                    4'd9,4'd10: O_row_bits=16'h0018;
                    4'd11,4'd12: O_row_bits=16'h0018;
                    4'd13,4'd14: O_row_bits=16'h07e0;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h28: begin // ( : doubled 5x7 glyph, same 16x16 cell as L/R/digits
                case(I_row)
                    4'd1,4'd2:O_row_bits=16'h0180;
                    4'd3,4'd4:O_row_bits=16'h0600;
                    4'd5,4'd6,4'd7,4'd8,4'd9,4'd10:O_row_bits=16'h1800;
                    4'd11,4'd12:O_row_bits=16'h0600;
                    4'd13,4'd14:O_row_bits=16'h0180;
                    default:O_row_bits=16'h0000;
                endcase
            end
            8'h29: begin // )
                case(I_row)
                    4'd1,4'd2:O_row_bits=16'h0600;
                    4'd3,4'd4:O_row_bits=16'h0180;
                    4'd5,4'd6,4'd7,4'd8,4'd9,4'd10:O_row_bits=16'h0060;
                    4'd11,4'd12:O_row_bits=16'h0180;
                    4'd13,4'd14:O_row_bits=16'h0600;
                    default:O_row_bits=16'h0000;
                endcase
            end
            8'h2c: begin // , : small bottom stroke, not a different-size font
                case(I_row)
                    4'd11,4'd12:O_row_bits=16'h0180;
                    4'd13,4'd14:O_row_bits=16'h0600;
                    default:O_row_bits=16'h0000;
                endcase
            end
            8'h2d: begin // - : centered 10x2 stroke
                case(I_row)
                    4'd7,4'd8:O_row_bits=16'h1ff8;
                    default:O_row_bits=16'h0000;
                endcase
            end
            8'h2e: begin // . : same doubled 5x7 glyph geometry
                case(I_row)
                    4'd13,4'd14:O_row_bits=16'h0180;
                    default:O_row_bits=16'h0000;
                endcase
            end
            8'h3a: begin // :
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h0000;
                    4'd3,4'd4: O_row_bits=16'h0180;
                    4'd5,4'd6: O_row_bits=16'h0180;
                    4'd7,4'd8: O_row_bits=16'h0000;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0180;
                    4'd13,4'd14: O_row_bits=16'h0000;
                    default: O_row_bits=16'h0000;
                endcase
            end
            8'h3f: begin // ?
                case(I_row)
                    4'd1,4'd2: O_row_bits=16'h07e0;
                    4'd3,4'd4: O_row_bits=16'h1818;
                    4'd5,4'd6: O_row_bits=16'h0018;
                    4'd7,4'd8: O_row_bits=16'h0060;
                    4'd9,4'd10: O_row_bits=16'h0180;
                    4'd11,4'd12: O_row_bits=16'h0000;
                    4'd13,4'd14: O_row_bits=16'h0180;
                    default: O_row_bits=16'h0000;
                endcase
            end
            default: O_row_bits=16'h0000;
        endcase
    end
endmodule
