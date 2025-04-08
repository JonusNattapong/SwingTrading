//+------------------------------------------------------------------+
//|                                               SwingTradingEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"
#property description "Expert Advisor based on the Swing Trading Plan"
#property strict

#include <Trade/Trade.mqh> // Include Trade library for order management

//--- Input parameters
input group           "Risk Management"
input double          InpRiskPercent       = 1.0;    // Risk per trade as % of Account Equity
input double          InpMinRiskRewardRatio = 1.5;    // Minimum Risk:Reward Ratio for TP

input group           "Indicator Settings"
// Stochastic Oscillator
input int             InpStochKPeriod      = 14;     // Stochastic %K period
input int             InpStochDPeriod      = 3;      // Stochastic %D period
input int             InpStochSlowing      = 3;      // Stochastic slowing
input ENUM_MA_METHOD  InpStochMAMethod     = MODE_SMA; // Stochastic Moving Average method
input double          InpStochOverbought   = 80.0;   // Stochastic Overbought level
input double          InpStochOversold     = 20.0;   // Stochastic Oversold level
// MACD
input int             InpMacdFastEMA       = 12;     // MACD Fast EMA period
input int             InpMacdSloeEMA       = 26;     // MACD Slow EMA period
input int             InpMacdSignalSMA     = 9;      // MACD Signal Line SMA period
input ENUM_APPLIED_PRICE InpMacdAppliedPrice = PRICE_CLOSE; // MACD Applied Price
// Fibonacci (Levels used in logic, not direct inputs here)

input group           "Trading Logic"
input ENUM_TIMEFRAMES InpTradingTimeframe  = PERIOD_H4; // Timeframe for primary signals
input int             InpTrendMAPeriod     = 50;     // Moving Average period for Trend Filter

input group           "Trade Management"
input bool            InpUseTrailingStop   = true;   // Enable Trailing Stop Loss
input int             InpTrailingStopPips  = 50;     // Trailing Stop distance in Pips (e.g., 50 pips for H4)

input group           "Breakout Settings"
input int             InpBreakoutRangeBars = 20;     // Number of bars to define High/Low range for Breakout
input int             InpBreakoutThresholdPips = 5;  // Minimum pips price must break range by

//--- Global variables
CTrade         trade;                     // Trade object
MqlTick        latest_tick;               // To store the latest tick info
datetime       last_bar_time = 0;         // Time of the last processed bar
int            stoch_handle = INVALID_HANDLE;
int            macd_handle = INVALID_HANDLE;
int            trend_ma_handle = INVALID_HANDLE; // Handle for Trend MA
// Add handles for other indicators if needed (e.g., MA for trend)

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- Initialize indicators
   stoch_handle = iStochastic(Symbol(), InpTradingTimeframe, InpStochKPeriod, InpStochDPeriod, InpStochSlowing, InpStochMAMethod, STO_LOWHIGH);
   if(stoch_handle == INVALID_HANDLE)
     {
      printf("Error creating Stochastic indicator handle - Error code: %d", GetLastError());
      return(INIT_FAILED);
     }

   macd_handle = iMACD(Symbol(), InpTradingTimeframe, InpMacdFastEMA, InpMacdSloeEMA, InpMacdSignalSMA, InpMacdAppliedPrice);
   if(macd_handle == INVALID_HANDLE)
     {
      printf("Error creating MACD indicator handle - Error code: %d", GetLastError());
      return(INIT_FAILED);
     }

   trend_ma_handle = iMA(Symbol(), InpTradingTimeframe, InpTrendMAPeriod, 0, MODE_SMA, PRICE_CLOSE);
   if(trend_ma_handle == INVALID_HANDLE)
     {
      printf("Error creating Trend MA indicator handle - Error code: %d", GetLastError());
      return(INIT_FAILED);
     }

//--- Initialize trade object
   trade.SetExpertMagicNumber(12345); // Set a unique magic number for this EA
   trade.SetDeviationInPoints(10);    // Allowable slippage in points
   trade.SetTypeFillingBySymbol(Symbol());

//--- Reset last bar time
   last_bar_time = 0;

//--- Success
   printf("SwingTradingEA initialized successfully.");
   return(INIT_SUCCEEDED);
  }
//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
//--- Release indicator handles
   if(stoch_handle != INVALID_HANDLE)
      IndicatorRelease(stoch_handle);
   if(macd_handle != INVALID_HANDLE)
      IndicatorRelease(macd_handle);
   if(trend_ma_handle != INVALID_HANDLE)
      IndicatorRelease(trend_ma_handle);
   printf("SwingTradingEA deinitialized. Reason code: %d", reason);
  }
//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
//--- Get the latest price data
   if(!SymbolInfoTick(Symbol(), latest_tick))
     {
      // Failed to get tick, maybe market closed or connection issue
      return;
     }

//--- Check for a new bar on the trading timeframe
   datetime current_bar_time = (datetime)SeriesInfoInteger(Symbol(), InpTradingTimeframe, SERIES_LASTBAR_DATE);
   bool is_new_bar = false;
   if(current_bar_time > last_bar_time)
     {
      last_bar_time = current_bar_time;
      is_new_bar = true;
     }

//--- Only execute logic once per bar
   if(!is_new_bar)
     {
      return; // Wait for the next bar
     }

//--- Check if allowed to trade
   if(!IsTradeAllowed())
     {
      // Trading is disabled in terminal settings or by account properties
      return;
     }

//--- Check if there are open positions (basic check, can be expanded)
   // bool position_exists = PositionSelect(Symbol()); // Simple check if any position exists for the symbol

//--- === Main Trading Logic ===

   // --- Check if a position already exists for this symbol ---
   // Basic check: Only allow one trade at a time per symbol for this EA instance
   if(PositionSelect(Symbol()))
     {
      // Position exists, don't open another one. Add management logic later if needed.
      return;
     }

   // --- Get Price Data for the last closed bar ---
   MqlRates rates[];
   if(CopyRates(Symbol(), InpTradingTimeframe, 1, 3, rates) < 3) // Get last 3 bars data
     {
      printf("Error copying rates history.");
      return;
     }
   double last_close = rates[0].close; // Index 0 is the most recently closed bar
   double last_high = rates[0].high;
   double last_low = rates[0].low;
   double prev_close = rates[1].close; // Bar before the last closed one

   // --- Get Indicator Values for the last closed bar ---
   double stoch_main_arr[], stoch_signal_arr[];
   double macd_main_arr[], macd_signal_arr[];
   double trend_ma_arr[];

   // Copy data for the last 3 bars (index 0 = current forming, 1 = last closed, 2 = previous)
   if(CopyBuffer(stoch_handle, 0, 0, 3, stoch_main_arr) <= 0 || CopyBuffer(stoch_handle, 1, 0, 3, stoch_signal_arr) <= 0)
     { printf("Error copying Stochastic buffers"); return; }
   if(CopyBuffer(macd_handle, 0, 0, 3, macd_main_arr) <= 0 || CopyBuffer(macd_handle, 1, 0, 3, macd_signal_arr) <= 0)
     { printf("Error copying MACD buffers"); return; }
   if(CopyBuffer(trend_ma_handle, 0, 0, 3, trend_ma_arr) <= 0)
     { printf("Error copying Trend MA buffer"); return; }

   // Values for the most recently closed bar (index 1)
   double stoch_main = stoch_main_arr[1];
   double stoch_signal = stoch_signal_arr[1];
   double macd_main = macd_main_arr[1];
   double macd_signal = macd_signal_arr[1];
   // Values for the previous bar (index 2)
   double prev_stoch_main = stoch_main_arr[2];
   double prev_stoch_signal = stoch_signal_arr[2];
   double prev_macd_main = macd_main_arr[2];
   double prev_macd_signal = macd_signal_arr[2];
   double trend_ma = trend_ma_arr[1]; // MA value for the last closed bar

   // --- Define Entry Conditions ---
   bool buy_reversal_signal = false;
   bool sell_reversal_signal = false;
   bool buy_breakout_signal = false; // Simplified - requires range definition
   bool sell_breakout_signal = false; // Simplified - requires range definition

   // --- Check Reversal Conditions (Simplified) ---
   // Buy Reversal: Stochastic was Oversold and is now crossing up, MACD confirms bullish momentum, AND Price is above Trend MA
   if (prev_stoch_main < InpStochOversold && stoch_main > InpStochOversold && stoch_main > stoch_signal) // Stochastic exit oversold & main > signal
     {
      if (macd_main > macd_signal) // MACD bullish confirmation
        {
         if(last_close > trend_ma) // Trend Filter: Price above MA
           {
            buy_reversal_signal = true;
            Print("Buy Reversal Signal: Stoch crossed up from Oversold, MACD bullish, Price > MA(", InpTrendMAPeriod, ").");
           }
         else
           { Print("Buy Reversal Signal Filtered: Price below MA."); }
        }
     }

   // Sell Reversal: Stochastic was Overbought and is now crossing down, MACD confirms bearish momentum, AND Price is below Trend MA
   if (prev_stoch_main > InpStochOverbought && stoch_main < InpStochOverbought && stoch_main < stoch_signal) // Stochastic exit overbought & main < signal
     {
      if (macd_main < macd_signal) // MACD bearish confirmation
        {
          if(last_close < trend_ma) // Trend Filter: Price below MA
           {
             sell_reversal_signal = true;
             Print("Sell Reversal Signal: Stoch crossed down from Overbought, MACD bearish, Price < MA(", InpTrendMAPeriod, ").");
           }
          else
           { Print("Sell Reversal Signal Filtered: Price above MA."); }
        }
     }

   // --- Check Breakout Conditions (Simplified Range Break) ---
   if(InpBreakoutRangeBars > 0)
     {
      // Get historical data for range calculation (start from bar index 2, look back InpBreakoutRangeBars)
      MqlRates range_rates[];
      if(CopyRates(Symbol(), InpTradingTimeframe, 2, InpBreakoutRangeBars, range_rates) == InpBreakoutRangeBars)
        {
         double highest_high = range_rates[0].high;
         double lowest_low = range_rates[0].low;
         for(int i = 1; i < InpBreakoutRangeBars; i++)
           {
            if(range_rates[i].high > highest_high) highest_high = range_rates[i].high;
            if(range_rates[i].low < lowest_low) lowest_low = range_rates[i].low;
           }

         double breakout_threshold_points = InpBreakoutThresholdPips * Point();

         // Check for Buy Breakout
         if(last_close > highest_high + breakout_threshold_points) // Price broke above range high
           {
            if(prev_macd_main < prev_macd_signal && macd_main > macd_signal) // MACD bullish cross confirmation
              {
               buy_breakout_signal = true;
               Print("Buy Breakout Signal: Price broke above ", InpBreakoutRangeBars, "-bar high (", DoubleToString(highest_high,_Digits), "), MACD crossed up.");
              }
           }
         // Check for Sell Breakout
         else if(last_close < lowest_low - breakout_threshold_points) // Price broke below range low
           {
            if(prev_macd_main > prev_macd_signal && macd_main < macd_signal) // MACD bearish cross confirmation
              {
               sell_breakout_signal = true;
               Print("Sell Breakout Signal: Price broke below ", InpBreakoutRangeBars, "-bar low (", DoubleToString(lowest_low,_Digits), "), MACD crossed down.");
              }
           }
        }
      else
        { Print("Error copying rates for breakout range calculation."); }
     }


   // --- Combine Signals & Execute ---
   // Prioritize Reversals slightly? Or allow both? For now, check Reversal first.
   if(buy_reversal_signal)
     {
      // Calculate SL and TP
      double stop_loss_price = last_low - SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point() - (10 * Point()); // Example: Below last low + buffer
      double take_profit_price = last_close + (last_close - stop_loss_price) * InpMinRiskRewardRatio; // TP based on R:R

      Print("Attempting Buy Order: SL=", DoubleToString(stop_loss_price, _Digits), " TP=", DoubleToString(take_profit_price, _Digits));
      PlaceBuyOrder(stop_loss_price, take_profit_price);
     }
   else if(sell_reversal_signal)
     {
      // Calculate SL and TP
      double stop_loss_price = last_high + SymbolInfoInteger(Symbol(), SYMBOL_SPREAD) * Point() + (10 * Point()); // Example: Above last high + buffer
      double take_profit_price = last_close - (stop_loss_price - last_close) * InpMinRiskRewardRatio; // TP based on R:R

      Print("Attempting Sell Order: SL=", DoubleToString(stop_loss_price, _Digits), " TP=", DoubleToString(take_profit_price, _Digits));
      PlaceSellOrder(stop_loss_price, take_profit_price);
     }

   // --- Check Breakout Signals if no Reversal signal ---
   else if(buy_breakout_signal)
     {
      // Calculate SL and TP for Breakout
      double stop_loss_price = highest_high - (10 * Point()); // Example: Place SL just inside the broken range high + buffer
      double take_profit_price = last_close + (last_close - stop_loss_price) * InpMinRiskRewardRatio; // TP based on R:R

      Print("Attempting Buy Breakout Order: SL=", DoubleToString(stop_loss_price, _Digits), " TP=", DoubleToString(take_profit_price, _Digits));
      PlaceBuyOrder(stop_loss_price, take_profit_price);
     }
   else if(sell_breakout_signal)
     {
      // Calculate SL and TP for Breakout
      double stop_loss_price = lowest_low + (10 * Point()); // Example: Place SL just inside the broken range low + buffer
      double take_profit_price = last_close - (stop_loss_price - last_close) * InpMinRiskRewardRatio; // TP based on R:R

      Print("Attempting Sell Breakout Order: SL=", DoubleToString(stop_loss_price, _Digits), " TP=", DoubleToString(take_profit_price, _Digits));
      PlaceSellOrder(stop_loss_price, take_profit_price);
     }
   // --- Manage Existing Trades ---
   if(InpUseTrailingStop)
     {
      ManageTrailingStop();
     }

  }
//+------------------------------------------------------------------+
//| Helper Functions (Examples - To be implemented)                  |
//+------------------------------------------------------------------+

// Function to calculate position size based on risk %
double CalculatePositionSize(double stop_loss_pips)
  {
   if(stop_loss_pips <= 0) return 0.01; // Minimum lot size if SL is invalid

   double account_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double risk_amount = account_equity * (InpRiskPercent / 100.0);
   double tick_value = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
   double tick_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_SIZE);
   double point_value = tick_value / tick_size * Point(); // Value of 1 point movement

   if(point_value <= 0) return 0.01; // Safety check

   double sl_value_per_lot = stop_loss_pips * Point() * point_value; // Incorrect calculation - needs adjustment based on contract size

   // Correct calculation needs SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE)
   double contract_size = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_CONTRACT_SIZE);
   double loss_per_lot = stop_loss_pips * Point() * contract_size; // Simplified for Forex pairs usually

   // Adjust for quote currency if different from account currency (more complex)

   if(loss_per_lot <= 0) return 0.01;

   double lots = risk_amount / loss_per_lot;

   // Normalize and check against min/max lot size
   double min_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
   double max_lot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX);
   double lot_step = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_STEP);

   lots = MathFloor(lots / lot_step) * lot_step; // Normalize to lot step

   if(lots < min_lot) lots = min_lot;
   if(lots > max_lot) lots = max_lot;

   return lots;
  }

//--- Function to place a Buy Order
void PlaceBuyOrder(double sl_price, double tp_price)
  {
   double entry_price = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_ASK), _Digits);
   double stop_loss_pips = (entry_price - sl_price) / Point();
   double lots = CalculatePositionSize(stop_loss_pips);

   if(lots > 0)
     {
      trade.Buy(lots, Symbol(), entry_price, sl_price, tp_price, "Swing EA Buy");
     }
  }

//--- Function to place a Sell Order
void PlaceSellOrder(double sl_price, double tp_price)
  {
   double entry_price = NormalizeDouble(SymbolInfoDouble(Symbol(), SYMBOL_BID), _Digits);
   double stop_loss_pips = (sl_price - entry_price) / Point();
   double lots = CalculatePositionSize(stop_loss_pips);

   if(lots > 0)
     {
      trade.Sell(lots, Symbol(), entry_price, sl_price, tp_price, "Swing EA Sell");
     }
  }

//--- Function to check if trading is allowed
bool IsTradeAllowed()
  {
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      Print("Automated trading is disabled in terminal settings.");
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      Print("Automated trading is disabled for the account.");
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Trailing Stop Loss Function                                      |
//+------------------------------------------------------------------+
void ManageTrailingStop()
  {
   if(InpTrailingStopPips <= 0) return; // Trailing stop must be positive

   double trail_distance_points = InpTrailingStopPips * Point(); // Convert pips to points

   // Iterate through all open positions
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      // Select position by index
      if(PositionGetTicket(i)) // Gets the ticket of the position at index i
        {
         // Check if the position belongs to this EA and this symbol
         if(PositionGetInteger(POSITION_MAGIC) == trade.ExpertMagicNumber() &&
            PositionGetString(POSITION_SYMBOL) == Symbol())
           {
            double current_sl = PositionGetDouble(POSITION_SL);
            double current_tp = PositionGetDouble(POSITION_TP); // Keep original TP
            double open_price = PositionGetDouble(POSITION_PRICE_OPEN);
            long position_type = PositionGetInteger(POSITION_TYPE); // POSITION_TYPE_BUY or POSITION_TYPE_SELL

            //--- Get current market prices
            double ask_price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
            double bid_price = SymbolInfoDouble(Symbol(), SYMBOL_BID);

            //--- Trailing for BUY positions
            if(position_type == POSITION_TYPE_BUY)
              {
               // Calculate potential new SL
               double new_sl = bid_price - trail_distance_points;

               // Check if position is in profit enough to trail
               if(bid_price > open_price + trail_distance_points)
                 {
                  // Check if the new SL is higher than the current SL (or if SL is 0)
                  if(new_sl > current_sl || current_sl == 0)
                    {
                     // Modify the position's SL
                     if(!trade.PositionModify(PositionGetTicket(i), new_sl, current_tp))
                       {
                        Print("Error modifying Buy position SL for trailing stop. Error code: ", GetLastError());
                       }
                     else
                       {
                        Print("Trailing Stop updated for Buy Ticket #", PositionGetTicket(i), " to ", DoubleToString(new_sl, _Digits));
                       }
                    }
                 }
              }
            //--- Trailing for SELL positions
            else if(position_type == POSITION_TYPE_SELL)
              {
               // Calculate potential new SL
               double new_sl = ask_price + trail_distance_points;

               // Check if position is in profit enough to trail
               if(ask_price < open_price - trail_distance_points)
                 {
                  // Check if the new SL is lower than the current SL (and SL is not 0)
                  if((new_sl < current_sl || current_sl == 0) && new_sl > 0) // Ensure new SL is positive
                    {
                     // Modify the position's SL
                     if(!trade.PositionModify(PositionGetTicket(i), new_sl, current_tp))
                       {
                        Print("Error modifying Sell position SL for trailing stop. Error code: ", GetLastError());
                       }
                     else
                       {
                        Print("Trailing Stop updated for Sell Ticket #", PositionGetTicket(i), " to ", DoubleToString(new_sl, _Digits));
                       }
                    }
                 }
              }
           }
        }
      else
        {
         Print("Error getting position ticket for index ", i, ". Error code: ", GetLastError());
        }
     }
  }
//+------------------------------------------------------------------+
