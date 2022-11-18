/*********************************************************************************
 SPDX-FileCopyrightText: 2021 , Dinesh Annayya                          
 
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

      http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
 SPDX-License-Identifier: Apache-2.0
 SPDX-FileContributor: Created by Dinesh Annayya <dinesh.annayya@gmail.com>

***********************************************************************************/
/**********************************************************************************
                                                              
                   RTC Top Module                                             
                                                              
  Description: RTC Top module Integrate
           A. RTC core
           B. RTC Reg
      
  To Do:                                                      
                                                              
  Author(s):                                                  
      - Dinesh Annayya, dinesh.annayya@gmail.com                 
                                                              
  Revision :                                                  
     0.0  - Oct 15, 2022 
            Initial Version picked from http://www.opencores.org/cores/rtc/
     0.1  - Nov 16, 2022
            Following changes are done
            1. Total design change to implement design running is RTC clock: 32768 Hz
            2. Timer Increment and Reset functionality correction
            3. Inteface change to Register interface instead of WB
            4. Maped the Most of Register to DS3231 format
            5. Alarm1/Alarm2 design correction
     0.2 - Nov 18, 2022
           1. Block is split as core and reg 
           2. Additional feature added
           3. Aligned 64 Bit RTC Time+ Date access support added
           4. RTC Halt/Reset config added
           5. fast mode is connected to register
                                                              
************************************************************************************/
/*********************************************************************************************
   Date Sheet Reference: https://datasheets.maximintegrated.com/en/ds/DS3231.pdf
   Register Decoding

   Addr    Bit-7   Bit-6   Bit-5   Bit-4   Bit-3   Bit-2   Bit-1   Bit-0  Function   Range
   0x00    0       <- 10   Second     ->   <-   Second                ->  Second     00-59
   0x01    0       <- 10   Minute     ->   <-   Minute                ->  Minute     00-59
   0x02    0       12      10 Hour 10 Hour <-   Hours                 ->  Hours      1 - 12
           0       24      PM/AM                                                     +AM/PM
                                                                                     00-23
   0x03    0       0       0       0       0       <-  DAY            ->  Day        01-07
   0x04    0       0       <- 10 Date ->   <-   Date                  ->  Date       01-31
   0x05    0       0       0       10 Month<-    Month                ->  Month      01-12
   0x06    <-  10 Year                ->   <-   Year                  ->  Year       00-99
   0x07    <   10 Century             ->   <-   Century               ->  Century    00-99
   0x08    <-       Alarm0 Time - Second                               ->
   0x09    <-       Alarm0 Time - Minute                               ->
   0x0A    <-       Alarm0 Time - Hour                                 ->
   0x0B    <-       Alarm0 Time - Day/Date                             ->
   0x0C    <-       Alarm1 Time - Second                               ->
   0x0D    <-       Alarm1 Time - Minute                               ->
   0x0E    <-       Alarm1 Time - Hour                                 ->
   0x0F    <-       Alarm1 Time - Day/Date                             ->
   0x10    <-    Alarm1 Ctrl          -><- Alarm0 Ctrl                 ->  Alarm Cntrl
   0x11                                                                -> Interrupt Enable
   0x12                                                                -> Interrupt Status

********************************************************************************************/

module rtc_top(
	// WISHBONE Interface
	input  logic        rtc_clk, 
    input  logic        rst_n, 


    input  logic        reg_cs, 
    input  logic [4:0]  reg_addr, 
    input  logic [31:0] reg_wdata, 
    input  logic [3:0]  reg_be, 
    input  logic        reg_wr, 
	output logic [31:0] reg_rdata, 
    output logic        reg_ack, 
    output logic        rtc_intr,

   // Debug Signals
   output  logic        inc_time_s,
   output  logic        inc_date_d

);
//--------------------------------------------------
// Local Wire decleration
//--------------------------------------------------
// RTC Core I/f
logic        cfg_rtc_update   ; // Update RTC core time/date with config
logic        cfg_rtc_capture  ; // Capture RTC core time/date with config
logic        cfg_rtc_halt     ; // Halt RTC Operation
logic        cfg_rtc_reset    ; // Reset RTC Operation
logic        cfg_fast_time    ; // Run Time is Fast Mode
logic        cfg_fast_date    ; // Run Date is Fast Mode
logic        cfg_hmode        ; // 12/24 hour mode
logic [31:0] cfg_time         ;
logic [31:0] cfg_date         ;

//---------------------------------------
// Increment Pulse
//----------------------------------------

//input logic             inc_time_s      ; // increment second
input logic             inc_time_ts     ; // increment tenth second
input logic             inc_time_m      ; // increment minute
input logic             inc_time_tm     ; // increment tenth minute
input logic             inc_time_h      ; // increment hour
input logic             inc_time_th     ; // increment tenth hour
input logic             inc_time_dow    ; // increment date of week
//input logic             inc_date_d      ; // increment date
input logic             inc_date_td     ; // increment tenth date
input logic             inc_date_m      ; // increment month
input logic             inc_date_tm     ; // increment tength month
input logic             inc_date_y      ; // increment year
input logic             inc_date_ty     ; // increment tenth year
input logic             inc_date_c      ; // increment century
input logic             inc_date_tc     ; // increment tenth century

// Counters of RTC Time Register
//
logic	[3:0]		time_s          ;// Seconds counter
logic	[2:0]		time_ts         ;// Ten seconds counter
logic	[3:0]		time_m          ;// Minutes counter
logic	[2:0]		time_tm         ;// Ten minutes counter
logic	[3:0]		time_h          ;// Hours counter
logic	[1:0]		time_th         ;// Ten hours counter
logic	[2:0]		time_dow        ;// Day of week counter
    
//
// Counter of RTC Date Register
//
logic	[3:0]		date_d          ;// Days counter
logic	[1:0]		date_td         ;// Ten days counter
logic	[3:0]		date_m          ;// Months counter
logic			    date_tm         ;// Ten months counter
logic	[3:0]		date_y          ;// Years counter
logic	[3:0]		date_ty         ;// Ten years counter
logic	[3:0]		date_c          ;// Centuries counter
logic	[3:0]		date_tc         ;// Ten centuries counter

rtc_core   u_core (
	// WISHBONE Interface
	.rtc_clk         (rtc_clk         ), 
    .rst_n           (rst_n           ), 

    // Counters of RTC Time Register
    //
    .time_s         (time_s        ) ,// Seconds counter
    .time_ts        (time_ts       ) ,// Ten seconds counter
    .time_m         (time_m        ) ,// Minutes counter
    .time_tm        (time_tm       ) ,// Ten minutes counter
    .time_h         (time_h        ) ,// Hours counter
    .time_th        (time_th       ) ,// Ten hours counter
    .time_dow       (time_dow      ) ,// Day of week counter
    
    //
    // Counter of RTC Date Register
    //
    .date_d         (date_d      ) ,// Days counter
    .date_td        (date_td     ) ,// Ten days counter
    .date_m         (date_m      ) ,// Months counter
    .date_tm        (date_tm     ) ,// Ten months counter
    .date_y         (date_y      ) ,// Years counter
    .date_ty        (date_ty     ) ,// Ten years counter
    .date_c         (date_c      ) ,// Centuries counter
    .date_tc        (date_tc     ) ,// Ten centuries counter

    // Increment Pulse

    .inc_time_s      (inc_time_s    ), // increment second
    .inc_time_ts     (inc_time_ts   ), // increment tenth second
    .inc_time_m      (inc_time_m    ), // increment minute
    .inc_time_tm     (inc_time_tm   ), // increment tenth minute
    .inc_time_h      (inc_time_h    ), // increment hour
    .inc_time_th     (inc_time_th   ), // increment tenth hour
    .inc_time_dow    (inc_time_dow  ), // increment date of week
    .inc_date_d      (inc_date_d    ), // increment date
    .inc_date_td     (inc_date_td   ), // increment tenth date
    .inc_date_m      (inc_date_m    ), // increment month
    .inc_date_tm     (inc_date_tm   ), // increment tength month
    .inc_date_y      (inc_date_y    ), // increment year
    .inc_date_ty     (inc_date_ty   ), // increment tenth year
    .inc_date_c      (inc_date_c    ), // increment century
    .inc_date_tc     (inc_date_tc   ), // increment tenth century


   // RTC Core I/f
    .fast_sim_time   (cfg_fast_time   ), // Run Time is Fast Mode
    .fast_sim_date   (cfg_fast_date   ), // Run Date is Fast Mode
    .cfg_rtc_update  (cfg_rtc_update  ),
    .cfg_rtc_capture (cfg_rtc_capture ),
    .cfg_rtc_halt    (cfg_rtc_halt    ),
    .cfg_rtc_reset   (cfg_rtc_reset   ),
    .cfg_hmode       (cfg_hmode       ), // 12/24 hour mode
    .cfg_time        (cfg_time        ),
    .cfg_date        (cfg_date        )


);


rtc_reg   u_reg(
	// WISHBONE Interface
	.rtc_clk         (rtc_clk           ), 
    .rst_n           (rst_n             ), 

    // Reg I/F

    .reg_cs          (reg_cs            ), 
    .reg_addr        (reg_addr          ), 
    .reg_wdata       (reg_wdata         ), 
    .reg_be          (reg_be            ), 
    .reg_wr          (reg_wr            ), 
	.reg_rdata       (reg_rdata         ), 
    .reg_ack         (reg_ack           ), 
    .rtc_intr        (rtc_intr          ),

    // Counters of RTC Time Register
    //
    .time_s         (time_s        ) ,// Seconds counter
    .time_ts        (time_ts       ) ,// Ten seconds counter
    .time_m         (time_m        ) ,// Minutes counter
    .time_tm        (time_tm       ) ,// Ten minutes counter
    .time_h         (time_h        ) ,// Hours counter
    .time_th        (time_th       ) ,// Ten hours counter
    .time_dow       (time_dow      ) ,// Day of week counter
    
    //
    // Counter of RTC Date Register
    //
    .date_d         (date_d      ) ,// Days counter
    .date_td        (date_td     ) ,// Ten days counter
    .date_m         (date_m      ) ,// Months counter
    .date_tm        (date_tm     ) ,// Ten months counter
    .date_y         (date_y      ) ,// Years counter
    .date_ty        (date_ty     ) ,// Ten years counter
    .date_c         (date_c      ) ,// Centuries counter
    .date_tc        (date_tc     ) ,// Ten centuries counter

    // Increment Pulse

    .inc_time_s      (inc_time_s    ), // increment second
    .inc_time_ts     (inc_time_ts   ), // increment tenth second
    .inc_time_m      (inc_time_m    ), // increment minute
    .inc_time_tm     (inc_time_tm   ), // increment tenth minute
    .inc_time_h      (inc_time_h    ), // increment hour
    .inc_time_th     (inc_time_th   ), // increment tenth hour
    .inc_time_dow    (inc_time_dow  ), // increment date of week
    .inc_date_d      (inc_date_d    ), // increment date
    .inc_date_td     (inc_date_td   ), // increment tenth date
    .inc_date_m      (inc_date_m    ), // increment month
    .inc_date_tm     (inc_date_tm   ), // increment tength month
    .inc_date_y      (inc_date_y    ), // increment year
    .inc_date_ty     (inc_date_ty   ), // increment tenth year
    .inc_date_c      (inc_date_c    ), // increment century
    .inc_date_tc     (inc_date_tc   ), // increment tenth century



   // RTC Core I/f
    .cfg_rtc_update  (cfg_rtc_update    ), // Update RTC core time/date with config
    .cfg_rtc_capture (cfg_rtc_capture   ), // Capture RTC core time/date with config
    .cfg_rtc_halt    (cfg_rtc_halt      ), // Halt RTC Operation
    .cfg_rtc_reset   (cfg_rtc_reset     ), // Reset RTC Operation
    .cfg_fast_time   (cfg_fast_time     ), // Run Time is Fast Mode
    .cfg_fast_date   (cfg_fast_date     ), // Run Date is Fast Mode
    .cfg_hmode       (cfg_hmode         ), // 12/24 hour mode
    .cfg_time        (cfg_time          ),
    .cfg_date        (cfg_date          )

);




endmodule
