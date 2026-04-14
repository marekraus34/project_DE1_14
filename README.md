# Audio Visualizer (PDM) – Nexys A7-50T

## Členové týmu

| Jméno | Role |
|---|---|
| Jan Maláč | PDM driver, top-level |
| Peter Rafaelis | PDM filtr, sensitivity_ctrl, testbench |
| Marek Raus | LED bar, peak_hold, dokumentace |

---

## Obsah

- [Cíl projektu](#cíl-projektu)
- [Lab 1: Architecture](#lab-1-architecture)
- [Lab 2: Unit Design](#lab-2-unit-design)
- [Lab 3: Integration](#lab-3-integration)
- [Lab 4: Tuning](#lab-4-tuning)
- [Lab 5: Defense](#lab-5-defense)

---

## Cíl projektu

Cílem projektu je zobrazení intenzity zvukového signálu v reálném čase pomocí 16 LED na desce Nexys A7-50T. Deska obsahuje zabudovaný MEMS mikrofon s PDM (Pulse Density Modulation) rozhraním. FPGA čte 1-bitový PDM datový tok, zpracuje ho decimačním filtrem a výslednou amplitudu zobrazí jako sloupcový VU metr na LED. Uživatel může pomocí tlačítek měnit citlivost a režim zobrazení.

### Základní funkce

- Čtení PDM dat z onboard MEMS mikrofonu
- Decimační filtr (akumulátor) pro převod PDM → amplituda
- Zobrazení hlasitosti na 16x LED jako VU metr
- Nastavitelná citlivost mikrofonu tlačítky BTNL / BTNR
- Režim Peak Hold – LED drží poslední maximum, přepíná BTNU
- Reset peak hodnoty tlačítkem BTND
- Reset celého systému tlačítkem BTNC

### Ovládání tlačítky

| Tlačítko | Pin | Funkce |
|---|---|---|
| **BTNC** | N17 | Reset – výchozí stav (citlivost střední, peak hold vypnutý) |
| **BTNL** | P17 | Snížení citlivosti – reaguje méně na slabé zvuky |
| **BTNR** | M17 | Zvýšení citlivosti – reaguje více na slabé zvuky |
| **BTNU** | M18 | Zapnutí / vypnutí režimu Peak Hold |
| **BTND** | P18 | Ruční reset peak hold hodnoty |

---

## Lab 1: Architecture

### Blokové schéma

*Viz soubor `img/block_diagram.png`*

```
zde bude schema hanz
```
## Lab 2: Unit Design

### debounce

Ošetřuje zákmity mechanických tlačítek. Vzorkuje vstup každé 2 ms pomocí posuvného registru a propustí stabilní hodnotu jako jednorázový pulz.

#### Porty

| Port | Směr | Typ | Popis |
|---|---|---|---|
| `clk` | in | std_logic | Hlavní hodiny 100 MHz |
| `rst` | in | std_logic | Synchronní reset, active high |
| `btn_i` | in | std_logic | Surový vstup tlačítka |
| `btn_o` | out | std_logic | Ošetřený výstup – 1 pulz na 1 stisk |

#### VHDL kód

```vhdl
library ieee;
  use ieee.std_logic_1164.all;

entity debounce is
    generic (
        G_MAX : positive := 200_000  -- 2 ms @ 100 MHz; pro simulaci použij 2
    );
    port (
        clk   : in  std_logic;
        rst   : in  std_logic;
        btn_i : in  std_logic;
        btn_o : out std_logic
    );
end entity debounce;

architecture Behavioral of debounce is

    signal ce_sample          : std_logic;
    signal shift_reg          : std_logic_vector(3 downto 0) := (others => '0');
    signal sync0, sync1       : std_logic := '0';
    signal debounced, delayed : std_logic := '0';

    component clk_en is
        generic ( G_MAX : positive );
        port ( clk : in std_logic; rst : in std_logic; ce : out std_logic );
    end component;

begin

    clk_en_inst : clk_en
        generic map ( G_MAX => G_MAX )
        port map ( clk => clk, rst => rst, ce => ce_sample );

    p_debounce : process (clk) is
    begin
        if rising_edge(clk) then
            if rst = '1' then
                sync0     <= '0';
                sync1     <= '0';
                shift_reg <= (others => '0');
                debounced <= '0';
                delayed   <= '0';
                btn_o     <= '0';
            else
                sync0 <= btn_i;
                sync1 <= sync0;
                if ce_sample = '1' then
                    shift_reg <= shift_reg(2 downto 0) & sync1;
                end if;
                if    shift_reg = "1111" then debounced <= '1';
                elsif shift_reg = "0000" then debounced <= '0';
                end if;
                delayed <= debounced;
                if debounced = '1' and delayed = '0' then
                    btn_o <= '1';
                else
                    btn_o <= '0';
                end if;
            end if;
        end if;
    end process p_debounce;

end architecture Behavioral;
```

---

---
zde bude pdm_driver i s vhdl kodem aji porty tam vlozi hanz
---
