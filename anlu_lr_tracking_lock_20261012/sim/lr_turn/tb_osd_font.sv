`timescale 1ns/1ps
module tb_osd_font;
reg [7:0] ch=0;
reg [3:0] row=0;
wire [15:0] bits;
osd_char_lib font(.I_char(ch),.I_row(row),.O_row_bits(bits));
integer c,r,col,n=0,top,bottom,fd;
reg [15:0] prev;
initial begin
 fd=$fopen("font_rows.txt","w");
 if(fd==0)$fatal(1,"font dump open failed");
 for(c=0;c<256;c=c+1)begin
  if((c>=65 && c<=90)||(c>=48 && c<=57)||c==58||c==63||c==128||c==129)begin
   ch=c;top=16;bottom=-1;prev=0;
   for(r=0;r<16;r=r+1)begin
    row=r;#1;
    $fdisplay(fd,"%02x %0d %04x",ch,r,bits);
    if(c!=128 && c!=129)begin
     if((r==0 || r==15) && bits!=0)$fatal(1,"glyph escapes 16x16 cell char=%0d row=%0d",c,r);
     if((bits & 16'he007)!=0)$fatal(1,"glyph escapes centered 10-pixel width char=%0d",c);
     if(r>0 && r<15 && r%2==0 && bits!==prev)$fatal(1,"glyph row scaling inconsistent char=%0d row=%0d",c,r);
     for(col=3;col<13;col=col+2)
      if(bits[15-col]!==bits[14-col])$fatal(1,"glyph column scaling inconsistent char=%0d col=%0d",c,col);
     if(bits!=0)begin if(top==16)top=r;bottom=r;end
    end
    prev=bits;
   end
   if((c>=65 && c<=90)||(c>=48 && c<=57))begin
    if(top!=1 || bottom!=14)$fatal(1,"unequal letter/digit height char=%0d top=%0d bottom=%0d",c,top,bottom);
    n=n+1;
   end
  end
 end
 // Existing Chinese strokes are unchanged; unsupported space is transparent.
 ch=128;row=0;#1;if(bits!==16'h0200)$fatal(1,"Chinese AN changed");
 ch=129;row=10;#1;if(bits!==16'h6220)$fatal(1,"Chinese LU changed");
 ch=32;row=8;#1;if(bits!==0)$fatal(1,"space is not transparent");
 $fclose(fd);
 $display("PASS OSD uniform font: %0d letters/digits, 16x16 cells / 10x14 strokes, punctuation, Chinese preserved",n);
 $finish;
end
endmodule
