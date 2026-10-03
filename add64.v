module add64(a,b,y,carry,overflow,zero);
    input [63:0] a;
    input [63:0] b;
    output [63:0] y;
    output carry;
    output overflow;
    output zero;
    wire [64:0] c;
    wire s1;
    wire s2;
    assign c[0]=1'b0;
    genvar i;
    generate
        for(i=0;i<64;i=i+1) begin:fa
            fulladder f(a[i],b[i],c[i],y[i],c[i+1]);
        end
    endgenerate
    assign carry=c[64];
    xor(s1,a[63],b[63]);
    xor(s2,a[63],y[63]);
    and(overflow,~s1,s2);
    nor(zero,
        y[0],y[1],y[2],y[3],y[4],y[5],y[6],y[7],
        y[8],y[9],y[10],y[11],y[12],y[13],y[14],y[15],
        y[16],y[17],y[18],y[19],y[20],y[21],y[22],y[23],
        y[24],y[25],y[26],y[27],y[28],y[29],y[30],y[31],
        y[32],y[33],y[34],y[35],y[36],y[37],y[38],y[39],
        y[40],y[41],y[42],y[43],y[44],y[45],y[46],y[47],
        y[48],y[49],y[50],y[51],y[52],y[53],y[54],y[55],
        y[56],y[57],y[58],y[59],y[60],y[61],y[62],y[63]);
endmodule
