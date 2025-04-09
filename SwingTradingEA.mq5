//+------------------------------------------------------------------+
//|                                                SwingTradingEA.mq5 |
//|                              Copyright 2025, Swing Trading System |
//|                                           https://github.com/JonusNattapong |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, Swing Trading System"
#property link      "https://github.com/JonusNattapong"
#property version   "1.00"

// Input parameters
input ENUM_TIMEFRAMES TimeFrame = PERIOD_H4;        // Trading timeframe (H4 or D1)
input double RiskPercent = 1.0;                     // Risk per trade (% of account)
input int StochPeriodK = 5;                         // Stochastic %K period
input int StochPeriodD = 3;                         // Stochastic %D period
input int StochSlowing = 3;                         // Stochastic slowing
input int MACDFast = 12;                            // MACD fast EMA period
input int MACDSlow = 26;                            // MACD slow EMA period
input int MACDSignal = 9;                           // MACD signal period
input bool UseReversal = true;                      // Use reversal strategy
input bool UseBreakout = true;                      // Use breakout strategy
input int FiboRetracementPeriod = 20;               // Period for Fibonacci retracement calculation
input double ReversalFiboLevel1 = 38.2;             // Fibonacci level 1 (%)
input double ReversalFiboLevel2 = 50.0;             // Fibonacci level 2 (%)
input double ReversalFiboLevel3 = 61.8;             // Fibonacci level 3 (%)
input int StochOverbought = 80;                     // Stochastic overbought level
input int StochOversold = 20;                       // Stochastic oversold level
input double TPRatio = 2.0;                         // Risk:Reward ratio for Take Profit

// Global variables
int stochHandle;                                    // Stochastic indicator handle
int macdHandle;                                     // MACD indicator handle
double stochBuffer[];                               // Stochastic %K values
double stochSignalBuffer[];                         // Stochastic %D values
double macdMainBuffer[];                            // MACD main line values
double macdSignalBuffer[];                          // MACD signal line values
double macdHistBuffer[];                            // MACD histogram values
double fiboLevels[];                                // Fibonacci levels

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   // Initialize Stochastic oscillator
   stochHandle = iStochastic(Symbol(), TimeFrame, StochPeriodK, StochPeriodD, StochSlowing, MODE_SMA, STO_LOWHIGH);
   if(stochHandle == INVALID_HANDLE)
   {
      Print("Error creating Stochastic indicator: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize MACD
   macdHandle = iMACD(Symbol(), TimeFrame, MACDFast, MACDSlow, MACDSignal, PRICE_CLOSE);
   if(macdHandle == INVALID_HANDLE)
   {
      Print("Error creating MACD indicator: ", GetLastError());
      return(INIT_FAILED);
   }
   
   // Initialize arrays
   ArraySetAsSeries(stochBuffer, true);
   ArraySetAsSeries(stochSignalBuffer, true);
   ArraySetAsSeries(macdMainBuffer, true);
   ArraySetAsSeries(macdSignalBuffer, true);
   ArraySetAsSeries(macdHistBuffer, true);
   
   // Set up Fibonacci levels
   ArrayResize(fiboLevels, 3);
   fiboLevels[0] = ReversalFiboLevel1 / 100.0;
   fiboLevels[1] = ReversalFiboLevel2 / 100.0;
   fiboLevels[2] = ReversalFiboLevel3 / 100.0;
   
   Print("Swing Trading EA initialized successfully");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Release indicator handles
   IndicatorRelease(stochHandle);
   IndicatorRelease(macdHandle);
   
   Print("Swing Trading EA removed");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   // Check if we are allowed to trade
   if(!IsTradeAllowed()) return;
   
   // Check if new bar has formed - we only trade on new bars
   if(!IsNewBar()) return;
   
   // Update indicator values
   if(!UpdateIndicators()) return;
   
   // Check for open positions
   if(PositionsTotal() > 0) 
   {
      ManageOpenPositions();
      return;
   }
   
   // Check for trading signals
   int signal = 0;
   
   // Check for reversal signals if enabled
   if(UseReversal)
   {
      signal = CheckReversalSignal();
      if(signal != 0)
      {
         ExecuteTradeSignal(signal);
         return;
      }
   }
   
   // Check for breakout signals if enabled
   if(UseBreakout)
   {
      signal = CheckBreakoutSignal();
      if(signal != 0)
      {
         ExecuteTradeSignal(signal);
         return;
      }
   }
}

//+------------------------------------------------------------------+
//| Check if a new bar has formed                                    |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   static datetime lastBarTime = 0;
   datetime currentBarTime = iTime(Symbol(), TimeFrame, 0);
   
   if(lastBarTime != currentBarTime)
   {
      lastBarTime = currentBarTime;
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Update all indicator values                                      |
//+------------------------------------------------------------------+
bool UpdateIndicators()
{
   // Copy Stochastic values
   if(CopyBuffer(stochHandle, 0, 0, 3, stochBuffer) < 3) return false;
   if(CopyBuffer(stochHandle, 1, 0, 3, stochSignalBuffer) < 3) return false;
   
   // Copy MACD values
   if(CopyBuffer(macdHandle, 0, 0, 3, macdMainBuffer) < 3) return false;
   if(CopyBuffer(macdHandle, 1, 0, 3, macdSignalBuffer) < 3) return false;
   if(CopyBuffer(macdHandle, 2, 0, 3, macdHistBuffer) < 3) return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Check for reversal trading signals                               |
//+------------------------------------------------------------------+
int CheckReversalSignal()
{
   // Get price data for Fibonacci levels
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyHigh(Symbol(), TimeFrame, 0, FiboRetracementPeriod, high) != FiboRetracementPeriod) return 0;
   if(CopyLow(Symbol(), TimeFrame, 0, FiboRetracementPeriod, low) != FiboRetracementPeriod) return 0;
   if(CopyClose(Symbol(), TimeFrame, 0, 3, close) != 3) return 0;
   
   // Calculate price swing for Fibonacci levels
   double highestPrice = high[ArrayMaximum(high, 0, FiboRetracementPeriod)];
   double lowestPrice = low[ArrayMinimum(low, 0, FiboRetracementPeriod)];
   double priceRange = highestPrice - lowestPrice;
   
   // Determine the main trend direction
   double ma50[], ma200[];
   ArraySetAsSeries(ma50, true);
   ArraySetAsSeries(ma200, true);
   
   if(CopyBuffer(iMA(Symbol(), TimeFrame, 50, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, ma50) != 2) return 0;
   if(CopyBuffer(iMA(Symbol(), TimeFrame, 200, 0, MODE_EMA, PRICE_CLOSE), 0, 0, 2, ma200) != 2) return 0;
   
   bool uptrend = ma50[0] > ma200[0];
   
   // BUY SIGNAL - Reversal from downtrend
   if(!uptrend) // In a downtrend looking for buy signals
   {
      // Check if price is near a Fibonacci retracement level
      bool nearFibLevel = false;
      for(int i = 0; i < ArraySize(fiboLevels); i++)
      {
         double fibLevel = lowestPrice + priceRange * fiboLevels[i];
         if(MathAbs(close[0] - fibLevel) < _Point * 10) // Within 10 pips of a Fib level
         {
            nearFibLevel = true;
            break;
         }
      }
      
      if(nearFibLevel &&
         stochBuffer[1] < StochOversold && stochBuffer[0] > StochOversold && // Stochastic crossing above oversold
         macdMainBuffer[0] > macdMainBuffer[1] && // MACD rising
         macdHistBuffer[0] > macdHistBuffer[1] && // MACD histogram rising
         CheckBullishPriceAction()) // Check for bullish price action
      {
         return 1; // BUY signal
      }
   }
   
   // SELL SIGNAL - Reversal from uptrend
   if(uptrend) // In an uptrend looking for sell signals
   {
      // Check if price is near a Fibonacci retracement level
      bool nearFibLevel = false;
      for(int i = 0; i < ArraySize(fiboLevels); i++)
      {
         double fibLevel = highestPrice - priceRange * fiboLevels[i];
         if(MathAbs(close[0] - fibLevel) < _Point * 10) // Within 10 pips of a Fib level
         {
            nearFibLevel = true;
            break;
         }
      }
      
      if(nearFibLevel &&
         stochBuffer[1] > StochOverbought && stochBuffer[0] < StochOverbought && // Stochastic crossing below overbought
         macdMainBuffer[0] < macdMainBuffer[1] && // MACD falling
         macdHistBuffer[0] < macdHistBuffer[1] && // MACD histogram falling
         CheckBearishPriceAction()) // Check for bearish price action
      {
         return -1; // SELL signal
      }
   }
   
   return 0; // No signal
}

//+------------------------------------------------------------------+
//| Check for breakout trading signals                               |
//+------------------------------------------------------------------+
int CheckBreakoutSignal()
{
   // Define range period for detecting consolidation
   int rangePeriod = 14;
   
   // Get price data
   double high[], low[], close[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyHigh(Symbol(), TimeFrame, 0, rangePeriod + 2, high) != rangePeriod + 2) return 0;
   if(CopyLow(Symbol(), TimeFrame, 0, rangePeriod + 2, low) != rangePeriod + 2) return 0;
   if(CopyClose(Symbol(), TimeFrame, 0, 3, close) != 3) return 0;
   
   // Find range (without current bar)
   double rangeHigh = high[ArrayMaximum(high, 1, rangePeriod)];
   double rangeLow = low[ArrayMinimum(low, 1, rangePeriod)];
   double rangeSize = rangeHigh - rangeLow;
   
   // Check if we have a valid range (not too wide, not too narrow)
   double atr = iATR(Symbol(), TimeFrame, 14, 1);
   if(rangeSize > atr * 5 || rangeSize < atr * 1.5) return 0; // Range not suitable
   
   // BUY SIGNAL - Breakout above resistance
   if(close[0] > rangeHigh + _Point * 5 && // Price closed above range high
      close[0] > close[1] && // Bullish candle
      macdHistBuffer[0] > macdHistBuffer[1] && // MACD histogram rising
      CheckBullishPriceAction()) // Bullish price action
   {
      return 1; // BUY signal
   }
   
   // SELL SIGNAL - Breakout below support
   if(close[0] < rangeLow - _Point * 5 && // Price closed below range low
      close[0] < close[1] && // Bearish candle
      macdHistBuffer[0] < macdHistBuffer[1] && // MACD histogram falling
      CheckBearishPriceAction()) // Bearish price action
   {
      return -1; // SELL signal
   }
   
   return 0; // No signal
}

//+------------------------------------------------------------------+
//| Check for bullish price action patterns                          |
//+------------------------------------------------------------------+
bool CheckBullishPriceAction()
{
   // Get OHLC data
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(Symbol(), TimeFrame, 0, 3, open) != 3) return false;
   if(CopyHigh(Symbol(), TimeFrame, 0, 3, high) != 3) return false;
   if(CopyLow(Symbol(), TimeFrame, 0, 3, low) != 3) return false;
   if(CopyClose(Symbol(), TimeFrame, 0, 3, close) != 3) return false;
   
   // Check for bullish engulfing pattern
   bool bullishEngulfing = (close[0] > open[0]) && // Current candle is bullish
                          (open[1] > close[1]) &&  // Previous candle is bearish
                          (open[0] < close[1]) &&  // Current open below previous close
                          (close[0] > open[1]);    // Current close above previous open
   
   // Check for hammer pattern
   double bodySize = MathAbs(open[0] - close[0]);
   double lowerWick = MathMin(open[0], close[0]) - low[0];
   double upperWick = high[0] - MathMax(open[0], close[0]);
   bool hammer = (close[0] > open[0]) && // Bullish candle
                (lowerWick > bodySize * 2) && // Lower wick at least twice the body size
                (upperWick < bodySize * 0.5); // Upper wick less than half the body size
   
   // Check for bullish pin bar
   bool bullishPinBar = (lowerWick > bodySize * 2) && // Long lower wick
                        (lowerWick > upperWick * 3) && // Lower wick much larger than upper wick
                        (low[0] < low[1]);            // New low formed
   
   return bullishEngulfing || hammer || bullishPinBar;
}

//+------------------------------------------------------------------+
//| Check for bearish price action patterns                          |
//+------------------------------------------------------------------+
bool CheckBearishPriceAction()
{
   // Get OHLC data
   double open[], high[], low[], close[];
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   if(CopyOpen(Symbol(), TimeFrame, 0, 3, open) != 3) return false;
   if(CopyHigh(Symbol(), TimeFrame, 0, 3, high) != 3) return false;
   if(CopyLow(Symbol(), TimeFrame, 0, 3, low) != 3) return false;
   if(CopyClose(Symbol(), TimeFrame, 0, 3, close) != 3) return false;
   
   // Check for bearish engulfing pattern
   bool bearishEngulfing = (close[0] < open[0]) && // Current candle is bearish
                          (open[1] < close[1]) &&  // Previous candle is bullish
                          (open[0] > close[1]) &&  // Current open above previous close
                          (close[0] < open[1]);    // Current close below previous open
   
   // Check for shooting star pattern
   double bodySize = MathAbs(open[0] - close[0]);
   double upperWick = high[0] - MathMax(open[0], close[0]);
   double lowerWick = MathMin(open[0], close[0]) - low[0];
   bool shootingStar = (close[0] < open[0]) && // Bearish candle
                      (upperWick > bodySize * 2) && // Upper wick at least twice the body size
                      (lowerWick < bodySize * 0.5); // Lower wick less than half the body size
   
   // Check for bearish pin bar
   bool bearishPinBar = (upperWick > bodySize * 2) && // Long upper wick
                        (upperWick > lowerWick * 3) && // Upper wick much larger than lower wick
                        (high[0] > high[1]);          // New high formed
   
   return bearishEngulfing || shootingStar || bearishPinBar;
}

//+------------------------------------------------------------------+
//| Execute a trade based on the signal                              |
//+------------------------------------------------------------------+
void ExecuteTradeSignal(int signal)
{
   if(signal == 0) return;
   
   double entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
   double stopLossPrice = 0.0;
   double takeProfitPrice = 0.0;
   double lotSize = 0.0;
   
   // Determine stop loss level based on price action
   if(signal > 0) // BUY
   {
      double recentLows[3];
      ArraySetAsSeries(recentLows, true);
      CopyLow(Symbol(), TimeFrame, 0, 3, recentLows);
      stopLossPrice = recentLows[ArrayMinimum(recentLows, 0, 3)] - _Point * 10; // 10 pips below the recent low
      
      // Calculate lot size based on risk
      double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
      double stopLossDistance = entryPrice - stopLossPrice;
      lotSize = NormalizeDouble(riskAmount / (stopLossDistance / _Point * 10), 2);
      
      // Calculate take profit based on Risk:Reward ratio
      takeProfitPrice = entryPrice + (entryPrice - stopLossPrice) * TPRatio;
      
      // Execute buy order
      if(PlaceOrder(ORDER_TYPE_BUY, entryPrice, lotSize, stopLossPrice, takeProfitPrice))
      {
         Print("BUY signal executed: ", Symbol(), " at ", entryPrice, ", SL: ", stopLossPrice, ", TP: ", takeProfitPrice);
      }
   }
   else if(signal < 0) // SELL
   {
      entryPrice = SymbolInfoDouble(Symbol(), SYMBOL_BID);
      
      double recentHighs[3];
      ArraySetAsSeries(recentHighs, true);
      CopyHigh(Symbol(), TimeFrame, 0, 3, recentHighs);
      stopLossPrice = recentHighs[ArrayMaximum(recentHighs, 0, 3)] + _Point * 10; // 10 pips above the recent high
      
      // Calculate lot size based on risk
      double riskAmount = AccountInfoDouble(ACCOUNT_BALANCE) * RiskPercent / 100;
      double stopLossDistance = stopLossPrice - entryPrice;
      lotSize = NormalizeDouble(riskAmount / (stopLossDistance / _Point * 10), 2);
      
      // Calculate take profit based on Risk:Reward ratio
      takeProfitPrice = entryPrice - (stopLossPrice - entryPrice) * TPRatio;
      
      // Execute sell order
      if(PlaceOrder(ORDER_TYPE_SELL, entryPrice, lotSize, stopLossPrice, takeProfitPrice))
      {
         Print("SELL signal executed: ", Symbol(), " at ", entryPrice, ", SL: ", stopLossPrice, ", TP: ", takeProfitPrice);
      }
   }
}

//+------------------------------------------------------------------+
//| Place an order with the specified parameters                     |
//+------------------------------------------------------------------+
bool PlaceOrder(ENUM_ORDER_TYPE orderType, double price, double lotSize, double stopLoss, double takeProfit)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Fill order request structure
   request.action = TRADE_ACTION_DEAL;
   request.symbol = Symbol();
   request.volume = lotSize;
   request.type = orderType;
   request.price = NormalizeDouble(price, _Digits);
   request.sl = NormalizeDouble(stopLoss, _Digits);
   request.tp = NormalizeDouble(takeProfit, _Digits);
   request.deviation = 10; // Allow slippage of 1 pip
   request.magic = 123456; // Magic number
   request.comment = "SwingTrading EA";
   request.type_filling = ORDER_FILLING_FOK;
   
   // Send order
   if(!OrderSend(request, result))
   {
      Print("Error placing order: ", GetLastError());
      return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
//| Manage open positions (trailing stop, etc.)                      |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket <= 0) continue;
      
      if(!PositionSelectByTicket(ticket)) continue;
      
      string symbol = PositionGetString(POSITION_SYMBOL);
      if(symbol != Symbol()) continue;
      
      ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentPrice = posType == POSITION_TYPE_BUY ? 
                          SymbolInfoDouble(Symbol(), SYMBOL_BID) : 
                          SymbolInfoDouble(Symbol(), SYMBOL_ASK);
      
      // Implement trailing stop if in profit
      if((posType == POSITION_TYPE_BUY && currentPrice > openPrice * 1.01) || // 1% in profit for BUY
         (posType == POSITION_TYPE_SELL && currentPrice < openPrice * 0.99))  // 1% in profit for SELL
      {
         double newSL = 0.0;
         
         if(posType == POSITION_TYPE_BUY)
         {
            // Move stop loss to break even + 10 pips if 1% in profit
            newSL = openPrice + _Point * 10;
            
            // Only modify if new stop loss is higher
            if(newSL > currentSL)
            {
               ModifyPosition(ticket, newSL, currentTP);
            }
         }
         else if(posType == POSITION_TYPE_SELL)
         {
            // Move stop loss to break even + 10 pips if 1% in profit
            newSL = openPrice - _Point * 10;
            
            // Only modify if new stop loss is lower
            if(newSL < currentSL || currentSL == 0)
            {
               ModifyPosition(ticket, newSL, currentTP);
            }
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Modify an existing position                                      |
//+------------------------------------------------------------------+
bool ModifyPosition(ulong ticket, double stopLoss, double takeProfit)
{
   MqlTradeRequest request = {};
   MqlTradeResult result = {};
   
   // Fill order request structure
   request.action = TRADE_ACTION_SLTP;
   request.position = ticket;
   request.symbol = Symbol();
   request.sl = NormalizeDouble(stopLoss, _Digits);
   request.tp = NormalizeDouble(takeProfit, _Digits);
   
   // Send the request
   if(!OrderSend(request, result))
   {
      Print("Error modifying position: ", GetLastError());
      return false;
   }
   
   return true;
}