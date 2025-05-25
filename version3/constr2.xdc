#Clock signal (100 MHz, pin W5 on Basys 3)
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { clk }]
#Reset button (e.g., BTNU on Basys 3, pin U18)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { btnC }]
#SPI outputs to Arduino via PMOD JB
# JB1
set_property -dict { PACKAGE_PIN A14 IOSTANDARD LVCMOS33 } [get_ports { sclk }];  
#set_property PULLDOWN true [get_ports sclk]
# JB2
set_property -dict { PACKAGE_PIN A16 IOSTANDARD LVCMOS33 } [get_ports { mosi }];
#set_property PULLDOWN true [get_ports mosi]
# JB3
set_property -dict { PACKAGE_PIN B15 IOSTANDARD LVCMOS33 } [get_ports { cs_n }];
#set_property PULLDOWN true [get_ports cs_n]


#set_property PACKAGE_PIN T18 [get_ports btnU]						
#	set_property IOSTANDARD LVCMOS33 [get_ports btnU]
set_property PACKAGE_PIN W19 [get_ports btnL]						
	set_property IOSTANDARD LVCMOS33 [get_ports btnL]
set_property PACKAGE_PIN T17 [get_ports btnR]						
	set_property IOSTANDARD LVCMOS33 [get_ports btnR]
#set_property PACKAGE_PIN U17 [get_ports btnD]						
#	set_property IOSTANDARD LVCMOS33 [get_ports btnD]
	
set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports {sw[0]}];
set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}];
set_property -dict { PACKAGE_PIN W16   IOSTANDARD LVCMOS33 } [get_ports {sw[2]}];
set_property -dict { PACKAGE_PIN W17   IOSTANDARD LVCMOS33 } [get_ports {sw[3]}];
set_property -dict { PACKAGE_PIN W15   IOSTANDARD LVCMOS33 } [get_ports {sw[4]}];
set_property -dict { PACKAGE_PIN V15   IOSTANDARD LVCMOS33 } [get_ports {sw[5]}];
set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {sw[6]}];
set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {sw[7]}];
set_property -dict { PACKAGE_PIN V2   IOSTANDARD LVCMOS33 } [get_ports {sw[8]}];
set_property -dict { PACKAGE_PIN T3   IOSTANDARD LVCMOS33 } [get_ports {sw[9]}];
set_property -dict { PACKAGE_PIN T2   IOSTANDARD LVCMOS33 } [get_ports {sw[10]}];
set_property -dict { PACKAGE_PIN R3   IOSTANDARD LVCMOS33 } [get_ports {sw[11]}];
set_property -dict { PACKAGE_PIN W2   IOSTANDARD LVCMOS33 } [get_ports {sw[12]}];
set_property -dict { PACKAGE_PIN U1   IOSTANDARD LVCMOS33 } [get_ports {sw[13]}];
set_property -dict { PACKAGE_PIN T1   IOSTANDARD LVCMOS33 } [get_ports {sw[14]}];
set_property -dict { PACKAGE_PIN R2   IOSTANDARD LVCMOS33 } [get_ports {sw[15]}];


#set_property -dict { PACKAGE_PIN W2    IOSTANDARD LVCMOS33 } [get_ports {sw_a[0]}]
#set_property -dict { PACKAGE_PIN U1    IOSTANDARD LVCMOS33 } [get_ports {sw_a[1]}]
#set_property -dict { PACKAGE_PIN T1    IOSTANDARD LVCMOS33 } [get_ports {sw_a[2]}]
#set_property -dict { PACKAGE_PIN R2    IOSTANDARD LVCMOS33 } [get_ports {sw_a[3]}]

#set_property -dict { PACKAGE_PIN W14   IOSTANDARD LVCMOS33 } [get_ports {sw_b[0]}]
#set_property -dict { PACKAGE_PIN W13   IOSTANDARD LVCMOS33 } [get_ports {sw_b[1]}]
#set_property -dict { PACKAGE_PIN V2    IOSTANDARD LVCMOS33 } [get_ports {sw_b[2]}]
#set_property -dict { PACKAGE_PIN T3    IOSTANDARD LVCMOS33 } [get_ports {sw_b[3]}]

set_property -dict { PACKAGE_PIN W7    IOSTANDARD LVCMOS33 } [get_ports { seg[0] }]; # CA
set_property -dict { PACKAGE_PIN W6    IOSTANDARD LVCMOS33 } [get_ports { seg[1] }]; # CB
set_property -dict { PACKAGE_PIN U8    IOSTANDARD LVCMOS33 } [get_ports { seg[2] }]; # CC
set_property -dict { PACKAGE_PIN V8    IOSTANDARD LVCMOS33 } [get_ports { seg[3] }]; # CD
set_property -dict { PACKAGE_PIN U5    IOSTANDARD LVCMOS33 } [get_ports { seg[4] }]; # CE
set_property -dict { PACKAGE_PIN V5    IOSTANDARD LVCMOS33 } [get_ports { seg[5] }]; # CF
set_property -dict { PACKAGE_PIN U7    IOSTANDARD LVCMOS33 } [get_ports { seg[6] }]; # CG
set_property -dict { PACKAGE_PIN U2    IOSTANDARD LVCMOS33 } [get_ports { an[0] }];  # AN0
set_property -dict { PACKAGE_PIN U4    IOSTANDARD LVCMOS33 } [get_ports { an[1] }];  # AN1
set_property -dict { PACKAGE_PIN V4    IOSTANDARD LVCMOS33 } [get_ports { an[2] }];  # AN2
set_property -dict { PACKAGE_PIN W4    IOSTANDARD LVCMOS33 } [get_ports { an[3] }];  # AN3


set_property PACKAGE_PIN U16 [get_ports {led[0]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[0]}]
set_property PACKAGE_PIN E19 [get_ports {led[1]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[1]}]
set_property PACKAGE_PIN U19 [get_ports {led[2]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[2]}]
set_property PACKAGE_PIN V19 [get_ports {led[3]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[3]}]
set_property PACKAGE_PIN W18 [get_ports {led[4]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[4]}]
set_property PACKAGE_PIN U15 [get_ports {led[5]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[5]}]
set_property PACKAGE_PIN U14 [get_ports {led[6]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[6]}]
set_property PACKAGE_PIN V14 [get_ports {led[7]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[7]}]
set_property PACKAGE_PIN V13 [get_ports {led[8]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[8]}]
set_property PACKAGE_PIN V3 [get_ports {led[9]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[9]}]
set_property PACKAGE_PIN W3 [get_ports {led[10]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[10]}]
set_property PACKAGE_PIN U3 [get_ports {led[11]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[11]}]
set_property PACKAGE_PIN P3 [get_ports {led[12]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[12]}]
set_property PACKAGE_PIN N3 [get_ports {led[13]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[13]}]
set_property PACKAGE_PIN P1 [get_ports {led[14]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[14]}]
set_property PACKAGE_PIN L1 [get_ports {led[15]}]					
	set_property IOSTANDARD LVCMOS33 [get_ports {led[15]}]

#set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
#set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
#set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
#set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
#set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
#set_property -dict { PACKAGE_PIN U15   IOSTANDARD LVCMOS33 } [get_ports {led[5]}]
#set_property -dict { PACKAGE_PIN U14   IOSTANDARD LVCMOS33 } [get_ports {led[6]}]
#set_property -dict { PACKAGE_PIN V14   IOSTANDARD LVCMOS33 } [get_ports {led[7]}]
#set_property -dict { PACKAGE_PIN V13   IOSTANDARD LVCMOS33 } [get_ports {led[8]}]
#set_property -dict { PACKAGE_PIN V3   IOSTANDARD LVCMOS33 } [get_ports {led[9]}]
#set_property -dict { PACKAGE_PIN W3   IOSTANDARD LVCMOS33 } [get_ports {led[10]}]
#set_property -dict { PACKAGE_PIN U3   IOSTANDARD LVCMOS33 } [get_ports {led[11]}]
#set_property -dict { PACKAGE_PIN P3   IOSTANDARD LVCMOS33 } [get_ports {led[12]}]
#set_property -dict { PACKAGE_PIN N3   IOSTANDARD LVCMOS33 } [get_ports {led[13]}]
#set_property -dict { PACKAGE_PIN P1   IOSTANDARD LVCMOS33 } [get_ports {led[14]}]
#set_property -dict { PACKAGE_PIN L1   IOSTANDARD LVCMOS33 } [get_ports {led[15]}]
