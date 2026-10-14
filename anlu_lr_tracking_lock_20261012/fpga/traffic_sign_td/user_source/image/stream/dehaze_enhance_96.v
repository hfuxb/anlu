`timescale 1ns/1ps
// Seven stages, fixed latency including bypass and arbitrary valid bubbles.
// Gamma 0.85 operates on Y=(R+2G+B)/4, adding the same delta to R/G/B.
// Lightweight causal 2x2 luma unsharp mask (current,left,up,up-left).
// Deadband +/-4 Y levels, 1/4 strength, final correction limited to +/-4.
// No coordinate displacement/row flushing, no variable multiplier/DSP.
module dehaze_enhance_96 #(parameter integer IMG_WIDTH=1280,IMG_HEIGHT=720)(
 input wire I_clk,I_rst_n,I_tvalid,I_tuser,I_tlast,I_enable,
 input wire [95:0] I_tdata,
 output reg O_tvalid,O_tuser,O_tlast,output reg [95:0] O_tdata);
 localparam integer GW=IMG_WIDTH/4;
 (* ram_style="block" *) reg [31:0] luma_line[0:GW-1];
 reg [95:0] rgb[0:5];reg [5:0] vp,up,lp,ep;
 reg enabled;reg [8:0] x;reg [9:0] y;
 reg [8:0] xp[0:5];reg [9:0] yp[0:5];
 reg [7:0] lum0[0:3],lum3[0:3];
 reg signed [9:0] gamma_delta[0:3];
 reg [31:0] old_line4;
 reg [7:0] left_luma,left_up;
 reg [9:0] blur_sum4[0:3];reg signed [9:0] detail5[0:3];
 function [7:0] gamma;
  input [7:0] value;begin case(value)
     8'd0:gamma=8'd0;
     8'd1:gamma=8'd2;
     8'd2:gamma=8'd4;
     8'd3:gamma=8'd6;
     8'd4:gamma=8'd7;
     8'd5:gamma=8'd9;
     8'd6:gamma=8'd11;
     8'd7:gamma=8'd12;
     8'd8:gamma=8'd13;
     8'd9:gamma=8'd15;
     8'd10:gamma=8'd16;
     8'd11:gamma=8'd18;
     8'd12:gamma=8'd19;
     8'd13:gamma=8'd20;
     8'd14:gamma=8'd22;
     8'd15:gamma=8'd23;
     8'd16:gamma=8'd24;
     8'd17:gamma=8'd26;
     8'd18:gamma=8'd27;
     8'd19:gamma=8'd28;
     8'd20:gamma=8'd29;
     8'd21:gamma=8'd31;
     8'd22:gamma=8'd32;
     8'd23:gamma=8'd33;
     8'd24:gamma=8'd34;
     8'd25:gamma=8'd35;
     8'd26:gamma=8'd37;
     8'd27:gamma=8'd38;
     8'd28:gamma=8'd39;
     8'd29:gamma=8'd40;
     8'd30:gamma=8'd41;
     8'd31:gamma=8'd43;
     8'd32:gamma=8'd44;
     8'd33:gamma=8'd45;
     8'd34:gamma=8'd46;
     8'd35:gamma=8'd47;
     8'd36:gamma=8'd48;
     8'd37:gamma=8'd49;
     8'd38:gamma=8'd51;
     8'd39:gamma=8'd52;
     8'd40:gamma=8'd53;
     8'd41:gamma=8'd54;
     8'd42:gamma=8'd55;
     8'd43:gamma=8'd56;
     8'd44:gamma=8'd57;
     8'd45:gamma=8'd58;
     8'd46:gamma=8'd59;
     8'd47:gamma=8'd61;
     8'd48:gamma=8'd62;
     8'd49:gamma=8'd63;
     8'd50:gamma=8'd64;
     8'd51:gamma=8'd65;
     8'd52:gamma=8'd66;
     8'd53:gamma=8'd67;
     8'd54:gamma=8'd68;
     8'd55:gamma=8'd69;
     8'd56:gamma=8'd70;
     8'd57:gamma=8'd71;
     8'd58:gamma=8'd72;
     8'd59:gamma=8'd73;
     8'd60:gamma=8'd75;
     8'd61:gamma=8'd76;
     8'd62:gamma=8'd77;
     8'd63:gamma=8'd78;
     8'd64:gamma=8'd79;
     8'd65:gamma=8'd80;
     8'd66:gamma=8'd81;
     8'd67:gamma=8'd82;
     8'd68:gamma=8'd83;
     8'd69:gamma=8'd84;
     8'd70:gamma=8'd85;
     8'd71:gamma=8'd86;
     8'd72:gamma=8'd87;
     8'd73:gamma=8'd88;
     8'd74:gamma=8'd89;
     8'd75:gamma=8'd90;
     8'd76:gamma=8'd91;
     8'd77:gamma=8'd92;
     8'd78:gamma=8'd93;
     8'd79:gamma=8'd94;
     8'd80:gamma=8'd95;
     8'd81:gamma=8'd96;
     8'd82:gamma=8'd97;
     8'd83:gamma=8'd98;
     8'd84:gamma=8'd99;
     8'd85:gamma=8'd100;
     8'd86:gamma=8'd101;
     8'd87:gamma=8'd102;
     8'd88:gamma=8'd103;
     8'd89:gamma=8'd104;
     8'd90:gamma=8'd105;
     8'd91:gamma=8'd106;
     8'd92:gamma=8'd107;
     8'd93:gamma=8'd108;
     8'd94:gamma=8'd109;
     8'd95:gamma=8'd110;
     8'd96:gamma=8'd111;
     8'd97:gamma=8'd112;
     8'd98:gamma=8'd113;
     8'd99:gamma=8'd114;
     8'd100:gamma=8'd115;
     8'd101:gamma=8'd116;
     8'd102:gamma=8'd117;
     8'd103:gamma=8'd118;
     8'd104:gamma=8'd119;
     8'd105:gamma=8'd120;
     8'd106:gamma=8'd121;
     8'd107:gamma=8'd122;
     8'd108:gamma=8'd123;
     8'd109:gamma=8'd124;
     8'd110:gamma=8'd125;
     8'd111:gamma=8'd126;
     8'd112:gamma=8'd127;
     8'd113:gamma=8'd128;
     8'd114:gamma=8'd129;
     8'd115:gamma=8'd130;
     8'd116:gamma=8'd131;
     8'd117:gamma=8'd132;
     8'd118:gamma=8'd132;
     8'd119:gamma=8'd133;
     8'd120:gamma=8'd134;
     8'd121:gamma=8'd135;
     8'd122:gamma=8'd136;
     8'd123:gamma=8'd137;
     8'd124:gamma=8'd138;
     8'd125:gamma=8'd139;
     8'd126:gamma=8'd140;
     8'd127:gamma=8'd141;
     8'd128:gamma=8'd142;
     8'd129:gamma=8'd143;
     8'd130:gamma=8'd144;
     8'd131:gamma=8'd145;
     8'd132:gamma=8'd146;
     8'd133:gamma=8'd147;
     8'd134:gamma=8'd148;
     8'd135:gamma=8'd149;
     8'd136:gamma=8'd149;
     8'd137:gamma=8'd150;
     8'd138:gamma=8'd151;
     8'd139:gamma=8'd152;
     8'd140:gamma=8'd153;
     8'd141:gamma=8'd154;
     8'd142:gamma=8'd155;
     8'd143:gamma=8'd156;
     8'd144:gamma=8'd157;
     8'd145:gamma=8'd158;
     8'd146:gamma=8'd159;
     8'd147:gamma=8'd160;
     8'd148:gamma=8'd161;
     8'd149:gamma=8'd162;
     8'd150:gamma=8'd162;
     8'd151:gamma=8'd163;
     8'd152:gamma=8'd164;
     8'd153:gamma=8'd165;
     8'd154:gamma=8'd166;
     8'd155:gamma=8'd167;
     8'd156:gamma=8'd168;
     8'd157:gamma=8'd169;
     8'd158:gamma=8'd170;
     8'd159:gamma=8'd171;
     8'd160:gamma=8'd172;
     8'd161:gamma=8'd172;
     8'd162:gamma=8'd173;
     8'd163:gamma=8'd174;
     8'd164:gamma=8'd175;
     8'd165:gamma=8'd176;
     8'd166:gamma=8'd177;
     8'd167:gamma=8'd178;
     8'd168:gamma=8'd179;
     8'd169:gamma=8'd180;
     8'd170:gamma=8'd181;
     8'd171:gamma=8'd182;
     8'd172:gamma=8'd182;
     8'd173:gamma=8'd183;
     8'd174:gamma=8'd184;
     8'd175:gamma=8'd185;
     8'd176:gamma=8'd186;
     8'd177:gamma=8'd187;
     8'd178:gamma=8'd188;
     8'd179:gamma=8'd189;
     8'd180:gamma=8'd190;
     8'd181:gamma=8'd191;
     8'd182:gamma=8'd191;
     8'd183:gamma=8'd192;
     8'd184:gamma=8'd193;
     8'd185:gamma=8'd194;
     8'd186:gamma=8'd195;
     8'd187:gamma=8'd196;
     8'd188:gamma=8'd197;
     8'd189:gamma=8'd198;
     8'd190:gamma=8'd199;
     8'd191:gamma=8'd199;
     8'd192:gamma=8'd200;
     8'd193:gamma=8'd201;
     8'd194:gamma=8'd202;
     8'd195:gamma=8'd203;
     8'd196:gamma=8'd204;
     8'd197:gamma=8'd205;
     8'd198:gamma=8'd206;
     8'd199:gamma=8'd207;
     8'd200:gamma=8'd207;
     8'd201:gamma=8'd208;
     8'd202:gamma=8'd209;
     8'd203:gamma=8'd210;
     8'd204:gamma=8'd211;
     8'd205:gamma=8'd212;
     8'd206:gamma=8'd213;
     8'd207:gamma=8'd214;
     8'd208:gamma=8'd214;
     8'd209:gamma=8'd215;
     8'd210:gamma=8'd216;
     8'd211:gamma=8'd217;
     8'd212:gamma=8'd218;
     8'd213:gamma=8'd219;
     8'd214:gamma=8'd220;
     8'd215:gamma=8'd221;
     8'd216:gamma=8'd221;
     8'd217:gamma=8'd222;
     8'd218:gamma=8'd223;
     8'd219:gamma=8'd224;
     8'd220:gamma=8'd225;
     8'd221:gamma=8'd226;
     8'd222:gamma=8'd227;
     8'd223:gamma=8'd228;
     8'd224:gamma=8'd228;
     8'd225:gamma=8'd229;
     8'd226:gamma=8'd230;
     8'd227:gamma=8'd231;
     8'd228:gamma=8'd232;
     8'd229:gamma=8'd233;
     8'd230:gamma=8'd234;
     8'd231:gamma=8'd234;
     8'd232:gamma=8'd235;
     8'd233:gamma=8'd236;
     8'd234:gamma=8'd237;
     8'd235:gamma=8'd238;
     8'd236:gamma=8'd239;
     8'd237:gamma=8'd240;
     8'd238:gamma=8'd240;
     8'd239:gamma=8'd241;
     8'd240:gamma=8'd242;
     8'd241:gamma=8'd243;
     8'd242:gamma=8'd244;
     8'd243:gamma=8'd245;
     8'd244:gamma=8'd246;
     8'd245:gamma=8'd246;
     8'd246:gamma=8'd247;
     8'd247:gamma=8'd248;
     8'd248:gamma=8'd249;
     8'd249:gamma=8'd250;
     8'd250:gamma=8'd251;
     8'd251:gamma=8'd252;
     8'd252:gamma=8'd252;
     8'd253:gamma=8'd253;
     8'd254:gamma=8'd254;
     8'd255:gamma=8'd255;
     default:gamma=value;
  endcase end
 endfunction
 function [7:0] luma;
  input [23:0] value;reg [9:0] sum;
  begin sum={2'd0,value[23:16]}+{1'b0,value[15:8],1'b0}+{2'd0,value[7:0]};luma=sum[9:2];end
 endfunction
 function [7:0] sat_add;
  input [7:0] value;input signed [9:0] delta;reg signed [10:0] sum;
  begin sum=$signed({1'b0,value})+delta;sat_add=sum<0?8'd0:sum>255?8'hff:sum[7:0];end
 endfunction
 function signed [9:0] sharpen;
  input signed [9:0] d;reg signed [9:0] magnitude,amount;
  begin magnitude=d<0?-d:d;
   if(magnitude<=4)sharpen=0;
   else begin amount=(magnitude-4)>>>2;if(amount>4)amount=4;sharpen=d<0?-amount:amount;end
  end
 endfunction
 reg [7:0] cur,prev,above,above_left;integer p,c,k;
 // S4 sync read; write previous stage on the same edge with read-before-write.
 // RAM is not reset; first-row mask excludes data from an earlier frame.
 always @(posedge I_clk)if(vp[3])begin
  old_line4<=luma_line[xp[3]];
  luma_line[xp[3]]<={lum3[3],lum3[2],lum3[1],lum3[0]};
 end
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   vp<=0;up<=0;lp<=0;ep<=0;enabled<=0;x<=0;y<=0;
   left_luma<=0;left_up<=0;O_tvalid<=0;O_tuser<=0;O_tlast<=0;O_tdata<=0;
   for(k=0;k<6;k=k+1)begin rgb[k]<=0;xp[k]<=0;yp[k]<=0;end
   for(k=0;k<4;k=k+1)begin lum0[k]<=0;lum3[k]<=0;gamma_delta[k]<=0;blur_sum4[k]<=0;detail5[k]<=0;end
  end else begin
   vp<={vp[4:0],I_tvalid};up<={up[4:0],I_tvalid&&I_tuser};lp<={lp[4:0],I_tvalid&&I_tlast};
   ep<={ep[4:0],(I_tvalid&&I_tuser)?I_enable:enabled};
   if(I_tvalid&&I_tuser)enabled<=I_enable;
   rgb[0]<=I_tdata;xp[0]<=I_tuser?9'd0:x;yp[0]<=I_tuser?10'd0:y;
   if(I_tvalid)begin
    if(I_tlast)begin x<=0;y<=(I_tuser?0:y)==IMG_HEIGHT-1?10'd0:(I_tuser?10'd1:y+1'b1);end
    else begin x<=(I_tuser?9'd0:x)+1'b1;y<=I_tuser?10'd0:y;end
   end
   for(k=1;k<6;k=k+1)begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];end
   for(p=0;p<4;p=p+1)begin
    lum0[p]<=luma(I_tdata[p*24+:24]);
    gamma_delta[p]<=$signed({1'b0,gamma(lum0[p])})-$signed({1'b0,lum0[p]});
   end
   rgb[1]<=rgb[0];
   for(p=0;p<4;p=p+1)for(c=0;c<3;c=c+1)
    rgb[2][p*24+c*8+:8]<=ep[1]?sat_add(rgb[1][p*24+c*8+:8],gamma_delta[p]):rgb[1][p*24+c*8+:8];
   rgb[3]<=rgb[2];rgb[4]<=rgb[3];rgb[5]<=rgb[4];
   for(p=0;p<4;p=p+1)lum3[p]<=luma(rgb[2][p*24+:24]);
   // S5: neighbors are in the preceding row and group; the first pixel of
   // every row replicates itself, never the last pixel of the previous row.
   if(vp[4])begin
    for(p=0;p<4;p=p+1)begin
     cur=luma(rgb[4][p*24+:24]);
     prev=p==0?(xp[4]==0?cur:left_luma):luma(rgb[4][(p-1)*24+:24]);
     above=yp[4]==0?cur:old_line4[p*8+:8];
     above_left=yp[4]==0?prev:(p==0?(xp[4]==0?above:left_up):old_line4[(p-1)*8+:8]);
     // Difference from the causal 2x2 mean; register before clamp/add.
     detail5[p]<=$signed({2'd0,cur})-$signed(({2'd0,cur}+{2'd0,prev}+{2'd0,above}+{2'd0,above_left})>>2);
    end
    left_luma<=luma(rgb[4][95:72]);left_up<=old_line4[31:24];
   end
   O_tvalid<=vp[5];O_tuser<=up[5];O_tlast<=lp[5];
   for(p=0;p<4;p=p+1)for(c=0;c<3;c=c+1)
    O_tdata[p*24+c*8+:8]<=ep[5]?sat_add(rgb[5][p*24+c*8+:8],sharpen(detail5[p])):rgb[5][p*24+c*8+:8];
  end
 end
endmodule
