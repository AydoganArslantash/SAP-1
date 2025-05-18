#Clock signal (100 MHz, pin W5 on Basys 3)
set_property -dict { PACKAGE_PIN W5 IOSTANDARD LVCMOS33 } [get_ports { clk }]
#Reset button (e.g., BTNU on Basys 3, pin U18)
set_property -dict { PACKAGE_PIN U18 IOSTANDARD LVCMOS33 } [get_ports { reset }]
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

set_property -dict { PACKAGE_PIN T17   IOSTANDARD LVCMOS33 } [get_ports { btn_write }];

set_property -dict { PACKAGE_PIN V17   IOSTANDARD LVCMOS33 } [get_ports { sw0 }];
#set_property -dict { PACKAGE_PIN V16   IOSTANDARD LVCMOS33 } [get_ports {sw[1]}]


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


set_property -dict { PACKAGE_PIN U16   IOSTANDARD LVCMOS33 } [get_ports {led[0]}]
set_property -dict { PACKAGE_PIN E19   IOSTANDARD LVCMOS33 } [get_ports {led[1]}]
set_property -dict { PACKAGE_PIN U19   IOSTANDARD LVCMOS33 } [get_ports {led[2]}]
set_property -dict { PACKAGE_PIN V19   IOSTANDARD LVCMOS33 } [get_ports {led[3]}]
set_property -dict { PACKAGE_PIN W18   IOSTANDARD LVCMOS33 } [get_ports {led[4]}]
