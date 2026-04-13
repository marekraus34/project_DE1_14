-------------------------------------------------
--! @brief PDM microphone driver
--! @version 1.0
--!
--! Generates microphone clock by dividing main clock
--! by G_CLK_DIV. Samples PDM data on rising edge of
--! mic_clk and outputs a single-cycle valid pulse.
--!
--! Nexys A7 onboard MEMS mic: ~3.125 MHz clock
--! (100 MHz / 32 = 3.125 MHz)
-------------------------------------------------
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
-------------------------------------------------
entity pdm_driver is
    generic (
        G_CLK_DIV : positive := 32  --! Clock divider (100 MHz / 32 = 3.125 MHz)
    );
    port (
        clk          : in  std_logic;  --! Main clock 100 MHz
        rst          : in  std_logic;  --! High-active synchronous reset
        mic_clk_o    : out std_logic;  --! Clock output to microphone
        mic_lr_sel_o : out std_logic;  --! Channel select: '0' = left
        mic_data_i   : in  std_logic;  --! PDM data from microphone
        pdm_data_o   : out std_logic;  --! Sampled PDM bit
        pdm_valid_o  : out std_logic   --! Single-cycle pulse = new valid bit
    );
end entity pdm_driver;
-------------------------------------------------
architecture Behavioral of pdm_driver is

    signal sig_cnt     : integer range 0 to G_CLK_DIV - 1 := 0;
    signal sig_clk_div : std_logic := '0';

begin

    --! Always use left channel
    mic_lr_sel_o <= '0';

    --! Divide main clock and sample PDM data on rising edge of mic_clk
    p_clk_div : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sig_cnt     <= 0;
                sig_clk_div <= '0';
                pdm_data_o  <= '0';
                pdm_valid_o <= '0';
            else
                pdm_valid_o <= '0';  -- Default: no valid pulse

                if sig_cnt = G_CLK_DIV - 1 then
                    sig_cnt     <= 0;
                    sig_clk_div <= not sig_clk_div;

                    -- Sample data on rising edge of mic_clk (when clk_div goes 0->1)
                    if sig_clk_div = '0' then
                        pdm_data_o  <= mic_data_i;
                        pdm_valid_o <= '1';
                    end if;
                else
                    sig_cnt <= sig_cnt + 1;
                end if;
            end if;
        end if;
    end process p_clk_div;

    mic_clk_o <= sig_clk_div;

end architecture Behavioral;
