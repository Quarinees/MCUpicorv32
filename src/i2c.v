module I2C(
input clk,
input start,
input DCn,
input [7:0] Data,
output reg busy=0,
output reg scl=1,
inout sda
);

parameter IDEL  = 0;
parameter START = 1;
parameter ADDR  = 2;
parameter CBYTE = 3;
parameter DATA  = 4;
parameter STOP  = 5;
parameter T_WAIT= 15;

//====================
// Open-drain SDA
//====================
reg sda_out = 1;     // value we want to drive
reg sda_oe  = 0;     // 1 = drive low, 0 = release

assign sda = (sda_oe && sda_out == 0) ? 1'b0 : 1'bz;
wire sda_in = sda;

//====================

reg DCn_r=0;
reg [2:0]state=0;
reg [3:0]i=0;
reg [3:0]step=0;
reg [12:0]delay=1;
reg [7:0]slave= 8'b01111000;   // SSD1306 address (0x3C << 1)
reg [7:0]cbyte= 8'b10000000;   // Control byte command
reg [7:0]dbyte= 8'b01000000;   // Control byte data
reg [7:0]data=  0;

always @(posedge clk)
begin

if(delay != 1)
begin
 delay<= delay-1;
end 
else 
begin

 case(state)

 //====================
 IDEL:
 begin
  scl<=1;
  sda_oe<=0;          // release bus
  if(start) 
  begin
     DCn_r<=DCn;
     data<=Data;
     busy<=1;
     state<= START;
     step<=0;
  end
 end

 //====================
 START:
 begin
  case(step)
  0: begin
      sda_out<=0;
      sda_oe<=1;      // pull SDA low
      delay<=T_WAIT;
      step<=1;
     end
  1: begin
      scl<=0;
      state<=ADDR;
      step<=0;
     end
  endcase
 end

 //====================
 ADDR:
 begin
  case(step)
  0: begin
      if(i<8)
      begin
          scl<=0;
          step<=1;
      end
      else if(i==8)   // ACK bit
      begin
          scl<=0;
          sda_oe<=0;  // release for ACK
          delay<=T_WAIT;
          i<=i+1;
          step<=2;
      end
     end

  1: begin
      if(slave[7-i]==0)
      begin
          sda_out<=0;
          sda_oe<=1;
      end
      else
          sda_oe<=0;

      delay<=T_WAIT-1;
      i<=i+1;
      step<=2;
     end

  2: begin
      if(i<9)
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=0;
      end
      else
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=3;
      end
     end

  3: begin
      scl<=0;
      delay<=T_WAIT;
      step<=4;
     end

  4: begin
      step<=0;
      i<=0;
      state<=CBYTE;
     end
  endcase
 end

 //====================
 CBYTE:
 begin
  case(step)
  0: begin
      if(i<8)
      begin
          scl<=0;
          step<=1;
      end
      else if(i==8)
      begin
          scl<=0;
          sda_oe<=0;  // release ACK
          delay<=T_WAIT;
          i<=i+1;
          step<=2;
      end
     end

  1: begin
      if(DCn_r ? dbyte[7-i] : cbyte[7-i])
          sda_oe<=0;
      else
      begin
          sda_out<=0;
          sda_oe<=1;
      end

      delay<=T_WAIT-1;
      i<=i+1;
      step<=2;
     end

  2: begin
      if(i<9)
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=0;
      end
      else
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=3;
      end
     end

  3: begin
      scl<=0;
      delay<=T_WAIT;
      step<=4;
     end

  4: begin
      step<=0;
      i<=0;
      state<=DATA;
     end
  endcase
 end

 //====================
 DATA:
 begin
  case(step)
  0: begin
      if(i<8)
      begin
          scl<=0;
          step<=1;
      end
      else if(i==8)
      begin
          scl<=0;
          sda_oe<=0;   // release ACK
          delay<=T_WAIT;
          i<=i+1;
          step<=2;
      end
     end

  1: begin
      if(data[7-i])
          sda_oe<=0;
      else
      begin
          sda_out<=0;
          sda_oe<=1;
      end

      delay<=T_WAIT-1;
      i<=i+1;
      step<=2;
     end

  2: begin
      if(i<9)
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=0;
      end
      else
      begin
          scl<=1;
          delay<=T_WAIT;
          step<=3;
      end
     end

  3: begin
      scl<=0;
      delay<=T_WAIT;
      step<=4;
     end

  4: begin
      step<=0;
      i<=0;
      state<=STOP;
     end
  endcase
 end

 //====================
 STOP:
 begin
  case(step)
  0: begin
      scl<=1;
      sda_out<=0;
      sda_oe<=1;
      delay<=T_WAIT;
      step<=1;
     end
  1: begin
      sda_oe<=0;     // release SDA high
      busy<=0;
      state<=IDEL;
      step<=0;
     end
  endcase
 end

 endcase
end
end

endmodule