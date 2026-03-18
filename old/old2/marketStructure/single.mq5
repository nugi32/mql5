//+------------------------------------------------------------------+
//|                     Swing Hit Zone EA                            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.1"
#property description "Swing Hit Zone - Improved Zone Management"
#property description "Detects swing highs/lows and creates trading zones"

//--- Input parameters
input int Depth = 10;                       // Swing detection depth
input int ConfirmBars = 3;                   // Confirmation bars

input group "=== Tailing Settings ==="
input double             Inp_Trailing_ParabolicSAR_Step   =0.02;
input double             Inp_Trailing_ParabolicSAR_Maximum=0.2;

input string   ORDER_SETUP = "============= ORDER SETUP =============";
input double lotSize = 0.01;                 // Ukuran lot
input int slBuffer = 10;                      // Stop loss buffer in points
input int      MagicNumber = 2024;            // Magic number
input int      Slippage = 10;                 // Slippage dalam points
input string   OrderComment = "Swing-Hit-Zone";  // Komentar order

//--- Zone management parameters
input int ZoneExpiryBars = 20;                // Number of bars before zone expires
input int MinZoneWidthPoints = 10;             // Minimum zone width in points
input int ZoneReactivationBars = 5;            // Bars before used zone can be reused
input bool DrawZonesOnChart = true;            // Draw zones on chart for visualization

//--- Global variables
int lastDirection = 0;
datetime lastTime = 0;
datetime lastBar  = 0;

int sarHandle;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
       sarHandle = iSAR(_Symbol,_Period,
                    Inp_Trailing_ParabolicSAR_Step,
                    Inp_Trailing_ParabolicSAR_Maximum);
                       if(sarHandle == INVALID_HANDLE)
   {
      Print("Failed to load SAR indicator");
      return INIT_FAILED;
   }

   Print("Swing Hit Zone EA initialized. Version 1.1");
   ResetZones();
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   // Clean up zone drawings
   for(int i = 0; i < 200; i++)
   {
      string zoneName = "ZONE_" + IntegerToString(i);
      ObjectDelete(0, zoneName);
      
      string textName = zoneName + "_TEXT";
      ObjectDelete(0, textName);
   }
         IndicatorRelease(sarHandle);
   Print("EA deinitialized. Reason: ", reason);
}

//+------------------------------------------------------------------+
void OnTick()
{
   datetime currentBar = iTime(_Symbol,_Period,0);

   if(currentBar == lastBar)
      return;

   lastBar = currentBar;

   Calculate();
   
   int dir;
   double sl,tp;

   if(PriceInValidZone(dir,sl,tp))
   {
      if(dir==1) // Sell signal
      {
         if(!HasOpenPosition())
         {
            OpenSellOrder(sl);
            CloseBuyPositions();
            Print("Sell order triggered at ", TimeToString(TimeCurrent()));
         }
      }
      else // Buy signal
      {
         if(!HasOpenPosition())
         {
            OpenBuyOrder(sl);
            CloseSellPositions();
            Print("Buy order triggered at ", TimeToString(TimeCurrent()));
         }
      }
   }
   
   // Draw zones if enabled
   if(DrawZonesOnChart)
      DrawZones();

double newSL;
TrailingParabolicSAR(_Symbol,newSL);
}

//+------------------------------------------------------------------+
void DrawArrow(string name, datetime t, double price, color clr, int code)
{
   if(ObjectFind(0,name) >= 0)
      return;

   ObjectCreate(0,name,OBJ_ARROW,0,t,price);
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,code);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,1);
}

//+------------------------------------------------------------------+
void Calculate()
{
   int rates_total = Bars(_Symbol,_Period);

   if(rates_total < Depth*2+5)
      return;

   double high[];
   double low[];
   datetime time[];

   ArraySetAsSeries(high,true);
   ArraySetAsSeries(low,true);
   ArraySetAsSeries(time,true);

   CopyHigh(_Symbol,_Period,0,rates_total,high);
   CopyLow(_Symbol,_Period,0,rates_total,low);
   CopyTime(_Symbol,_Period,0,rates_total,time);

   int start = rates_total - Depth*2 - 2;

   if(start < 1)
      start = 1;

   // Update current bar index for zone management
   currentBarIndex = rates_total;

   for(int i=start;i>0;i--)
   {
      //=====================
      // SWING HIGH
      //=====================

      int maxIndex = ArrayMaximum(high,i,Depth*2);

      if(maxIndex == i+Depth)
      {
         int swingIndex = i+Depth;

         double swingHigh = high[swingIndex];
         double swingLow  = low[swingIndex];

         double range = swingHigh - swingLow;
         double zone  = range/4.0;

         double hitLevel = swingHigh - zone;

         bool broken=false;

         int startCheck = swingIndex - ConfirmBars;
         if(startCheck < 0) startCheck = 0;

         for(int j=startCheck;j>=0;j--)
         {
            if(high[j] >= hitLevel)
            {
               broken=true;
               break;
            }
         }

         string name;

         if(broken)
         {
            name="HighBroken_"+IntegerToString(time[swingIndex]);
            DrawArrow(name,time[swingIndex],swingHigh,clrGray,234);
         }
         else
         {
            name="High_"+IntegerToString(time[swingIndex]);
            DrawArrow(name,time[swingIndex],swingHigh,clrGreen,234);

            // ADD ZONE HANYA JIKA VALID
            AddZone(swingHigh, hitLevel, time[swingIndex], 1);
         }

         lastDirection=1;
         lastTime=time[swingIndex];
      }

      //=====================
      // SWING LOW
      //=====================

      int minIndex = ArrayMinimum(low,i,Depth*2);
      if(minIndex == i+Depth)
      {
         int swingIndex = i+Depth;

         double swingHigh = high[swingIndex];
         double swingLow  = low[swingIndex];

         double range = swingHigh - swingLow;
         double zone  = range/4.0;

         double hitLevel = swingLow + zone;

         bool broken=false;

         int startCheck = swingIndex - ConfirmBars;
         if(startCheck < 0) startCheck = 0;

         for(int j=startCheck;j>=0;j--)
         {
            if(low[j] <= hitLevel)
            {
               broken=true;
               break;
            }
         }

         string name;

         if(broken)
         {
            name="LowBroken_"+IntegerToString(time[swingIndex]);
            DrawArrow(name,time[swingIndex],swingLow,clrYellow,233);
         }
         else
         {
            name="Low_"+IntegerToString(time[swingIndex]);
            DrawArrow(name,time[swingIndex],swingLow,clrRed,233);

            // ADD ZONE HANYA JIKA VALID
            AddZone(hitLevel, swingLow, time[swingIndex], -1);
         }

         lastDirection=-1;
         lastTime=time[swingIndex];
      }
   }
}

//+------------------------------------------------------------------+
//|                        Improved Zone Management                  |
//+------------------------------------------------------------------+

struct SwingZone
{
   double high;
   double low;
   datetime time;
   bool used;
   int direction;          // 1 = sell zone (swing high), -1 = buy zone (swing low)
   int barCreated;         // Bar index when zone was created
   bool active;            // Whether zone is still active
   int ticket;             // Associated order ticket (if any)
};

SwingZone zones[200];
int zoneCount = 0;
int currentBarIndex = 0;

//+------------------------------------------------------------------+
void AddZone(double high, double low, datetime t, int direction)
{
   // Minimum zone width check
   double minWidth = MinZoneWidthPoints * _Point;
   double zoneWidth = MathAbs(high - low);
   
   if(zoneWidth < minWidth && minWidth > 0)
   {
      // Expand zone to minimum width
      double midPrice = (high + low) / 2;
      high = midPrice + (minWidth / 2);
      low = midPrice - (minWidth / 2);
      Print("Zone expanded to minimum width: ", DoubleToString(zoneWidth/_Point, 0), 
            " -> ", MinZoneWidthPoints, " points at ", TimeToString(t));
   }
   
   // First, clean up any duplicate or overlapping zones
   for(int i = 0; i < zoneCount; i++)
   {
      // Check if zone with similar levels and same direction exists and is still active
      if(zones[i].direction == direction && zones[i].active)
      {
         // Check if zones overlap significantly (more than 50%)
         double overlapHigh = MathMin(high, zones[i].high);
         double overlapLow = MathMax(low, zones[i].low);
         
         if(overlapHigh > overlapLow) // There is overlap
         {
            double overlapSize = overlapHigh - overlapLow;
            double zoneSize = high - low;
            
            // If overlap is more than 50%, update existing zone instead of creating new one
            if(overlapSize > zoneSize * 0.5)
            {
               // Update existing zone to cover both ranges
               zones[i].high = MathMax(high, zones[i].high);
               zones[i].low = MathMin(low, zones[i].low);
               zones[i].time = t; // Update time to newest
               zones[i].used = false; // Reset used flag
               zones[i].barCreated = currentBarIndex;
               Print("Zone updated (overlap) at index ", i, " at ", TimeToString(t));
               return;
            }
         }
      }
   }
   
   // Check if we've reached maximum zones
   if(zoneCount >= 200)
   {
      // Find oldest inactive or used zone to replace
      int oldestIndex = -1;
      datetime oldestTime = TimeCurrent();
      
      for(int i = 0; i < zoneCount; i++)
      {
         if(!zones[i].active || zones[i].used)
         {
            if(zones[i].time < oldestTime)
            {
               oldestTime = zones[i].time;
               oldestIndex = i;
            }
         }
      }
      
      // If found an inactive zone, replace it
      if(oldestIndex >= 0)
      {
         zones[oldestIndex].high = high;
         zones[oldestIndex].low = low;
         zones[oldestIndex].time = t;
         zones[oldestIndex].used = false;
         zones[oldestIndex].direction = direction;
         zones[oldestIndex].barCreated = currentBarIndex;
         zones[oldestIndex].active = true;
         zones[oldestIndex].ticket = 0;
         Print("Zone replaced at index ", oldestIndex, " at ", TimeToString(t));
         return;
      }
      else
      {
         Print("Cannot add zone: maximum zones reached and all are active at ", TimeToString(t));
         return;
      }
   }
   
   // Add new zone
   zones[zoneCount].high = high;
   zones[zoneCount].low = low;
   zones[zoneCount].time = t;
   zones[zoneCount].used = false;
   zones[zoneCount].direction = direction;
   zones[zoneCount].barCreated = currentBarIndex;
   zones[zoneCount].active = true;
   zones[zoneCount].ticket = 0;
   
   Print("New zone added at index ", zoneCount, " Direction: ", direction, " Range: ", 
         DoubleToString(high, _Digits), " - ", DoubleToString(low, _Digits), " at ", TimeToString(t));
   
   zoneCount++;
}

//+------------------------------------------------------------------+
bool PriceInValidZone(int &dir, double &sl, double &tp)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // First, clean up expired zones
   CleanupZones();
   
   // Sort zones by time (newest first) for priority
   SortZonesByTime();
   
   // Check zones from newest to oldest
   for(int i = 0; i < zoneCount; i++)
   {
      // Skip if zone is not active or already used
      if(!zones[i].active || zones[i].used)
         continue;
      
      // For buy zones (direction = -1), check ask price (for buying)
      // For sell zones (direction = 1), check bid price (for selling)
      bool priceInZone = false;
      double currentPrice = 0;
      
      if(zones[i].direction == -1) // Buy zone
      {
         currentPrice = ask;
         // Check if ask is within the zone (for buy entries)
         if(ask >= zones[i].low && ask <= zones[i].high)
         {
            priceInZone = true;
         }
      }
      else if(zones[i].direction == 1) // Sell zone
      {
         currentPrice = bid;
         // Check if bid is within the zone (for sell entries)
         if(bid >= zones[i].low && bid <= zones[i].high)
         {
            priceInZone = true;
         }
      }
      
      if(priceInZone)
      {
         dir = zones[i].direction;
         
         // Mark as used but keep it active for a while to prevent re-entry
         zones[i].used = true;
         
         // Calculate SL and TP
         double zoneHeight = MathAbs(zones[i].high - zones[i].low);
         
         if(dir == 1) // sell
         {
            sl = zones[i].high + (slBuffer * _Point); // SL above the zone + buffer
            tp = zones[i].low - (zoneHeight * 2); // TP 2x zone height below
            
            Print("SELL signal in zone #", i, " Bid: ", bid, " Zone: ", 
                  DoubleToString(zones[i].low, _Digits), " - ", DoubleToString(zones[i].high, _Digits));
         }
         else // buy
         {
            sl = zones[i].low - (slBuffer * _Point); // SL below the zone - buffer
            tp = zones[i].high + (zoneHeight * 2); // TP 2x zone height above
            
            Print("BUY signal in zone #", i, " Ask: ", ask, " Zone: ", 
                  DoubleToString(zones[i].low, _Digits), " - ", DoubleToString(zones[i].high, _Digits));
         }
         
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
void CleanupZones()
{
   // Update current bar index
   currentBarIndex = Bars(_Symbol, _Period);
   
   for(int i = 0; i < zoneCount; i++)
   {
      // Deactivate zones that are too old
      if(zones[i].active)
      {
         int barsPassed = currentBarIndex - zones[i].barCreated;
         
         // Deactivate if zone is expired
         if(barsPassed > ZoneExpiryBars)
         {
            zones[i].active = false;
            Print("Zone ", i, " expired after ", barsPassed, " bars");
         }
         // Reactivate used zones after some bars to allow re-entry if price revisits
         else if(zones[i].used && barsPassed > ZoneReactivationBars)
         {
            zones[i].used = false;
            Print("Zone ", i, " reactivated after ", barsPassed, " bars");
         }
      }
   }
}

//+------------------------------------------------------------------+
void SortZonesByTime()
{
   // Simple bubble sort to put newest zones first
   for(int i = 0; i < zoneCount - 1; i++)
   {
      for(int j = 0; j < zoneCount - i - 1; j++)
      {
         if(zones[j].time < zones[j + 1].time)
         {
            // Swap zones
            SwingZone temp = zones[j];
            zones[j] = zones[j + 1];
            zones[j + 1] = temp;
         }
      }
   }
}

//+------------------------------------------------------------------+
void ResetZones()
{
   zoneCount = 0;
   currentBarIndex = 0;
   
   // Manual initialization instead of ArrayInitialize
   for(int i = 0; i < 200; i++)
   {
      zones[i].high = 0;
      zones[i].low = 0;
      zones[i].time = 0;
      zones[i].used = false;
      zones[i].direction = 0;
      zones[i].barCreated = 0;
      zones[i].active = false;
      zones[i].ticket = 0;
   }
   
   Print("All zones reset");
}

//+------------------------------------------------------------------+
void DrawZones()
{
   for(int i = 0; i < zoneCount; i++)
   {
      if(!zones[i].active) continue;
      
      string zoneName = "ZONE_" + IntegerToString(i);
      color zoneColor = zones[i].direction == 1 ? clrRed : clrBlue;
      
      if(zones[i].used)
         zoneColor = clrGray;
      
      // Delete old rectangle if exists
      ObjectDelete(0, zoneName);
      
      // Create new rectangle (extend 20 bars into the future)
      datetime time2 = zones[i].time + PeriodSeconds(_Period) * 20;
      
      ObjectCreate(0, zoneName, OBJ_RECTANGLE, 0, zones[i].time, zones[i].high, time2, zones[i].low);
      ObjectSetInteger(0, zoneName, OBJPROP_COLOR, zoneColor);
      ObjectSetInteger(0, zoneName, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, zoneName, OBJPROP_BACK, true);
      ObjectSetInteger(0, zoneName, OBJPROP_FILL, true);
      ObjectSetInteger(0, zoneName, OBJPROP_WIDTH, 1);
      
      // Add text label
      string textName = zoneName + "_TEXT";
      ObjectDelete(0, textName);
      
      string zoneType = zones[i].direction == 1 ? "SELL ZONE" : "BUY ZONE";
      string status = zones[i].used ? " (USED)" : " (ACTIVE)";
      
      ObjectCreate(0, textName, OBJ_TEXT, 0, zones[i].time + PeriodSeconds(_Period) * 5, 
                   (zones[i].high + zones[i].low) / 2);
      ObjectSetString(0, textName, OBJPROP_TEXT, zoneType + status);
      ObjectSetInteger(0, textName, OBJPROP_COLOR, zoneColor);
      ObjectSetInteger(0, textName, OBJPROP_FONTSIZE, 8);
   }
}

//+------------------------------------------------------------------+
//| Helper Functions                                                 |
//+------------------------------------------------------------------+

bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC) == MagicNumber &&
            PositionGetString(POSITION_SYMBOL) == _Symbol)
         {
            return true;
         }
      }
   }
   return false;
}

//+------------------------------------------------------------------+
void CloseBuyPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_BUY)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.volume   = volume;
      request.type     = ORDER_TYPE_SELL;
      request.price    = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      request.deviation= Slippage;
      request.magic    = MagicNumber;
      request.comment  = "Close BUY by EA";
      request.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(request, result))
         Print("BUY closed: Ticket=", ticket, " Retcode=", result.retcode);
      else
         Print("Failed close BUY: Ticket=", ticket, " Error=", result.retcode);
   }
}

//+------------------------------------------------------------------+
void CloseSellPositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      if(PositionGetInteger(POSITION_TYPE) != POSITION_TYPE_SELL)
         continue;

      double volume = PositionGetDouble(POSITION_VOLUME);

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};

      request.action   = TRADE_ACTION_DEAL;
      request.position = ticket;
      request.symbol   = _Symbol;
      request.volume   = volume;
      request.type     = ORDER_TYPE_BUY;
      request.price    = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      request.deviation= Slippage;
      request.magic    = MagicNumber;
      request.comment  = "Close SELL by EA";
      request.type_filling = ORDER_FILLING_FOK;

      if(OrderSend(request, result))
         Print("SELL closed: Ticket=", ticket, " Retcode=", result.retcode);
      else
         Print("Failed close SELL: Ticket=", ticket, " Error=", result.retcode);
   }
}

//+------------------------------------------------------------------+
void OpenBuyOrder(double slPrice)
{
   if (HasOpenPosition()) 
   {
      Print("Cannot open BUY: Position already exists");
      return;
   }

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   
   // Ensure SL is below entry for buy
   if(slPrice >= entryPrice)
   {
      slPrice = entryPrice - (10 * _Point);
      Print("SL adjusted to be below entry price");
   }

   MqlTradeRequest request={};
   MqlTradeResult result={};

   request.action = TRADE_ACTION_DEAL;
   request.magic = MagicNumber;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.price = entryPrice;
   request.sl = slPrice;
   request.tp = 0;
   request.deviation = Slippage;
   request.type = ORDER_TYPE_BUY;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = OrderComment;

   if(OrderSend(request, result))
   {
      Print("BUY order opened: Ticket=", result.order, " Price=", entryPrice, " SL=", slPrice);
      
      // Store ticket in the zone that triggered the trade
      for(int i = 0; i < zoneCount; i++)
      {
         if(zones[i].direction == -1 && zones[i].used && zones[i].ticket == 0)
         {
            zones[i].ticket = (int)result.order;
            break;
         }
      }
   }
   else
   {
      Print("Failed to open BUY order. Error: ", GetLastError());
   }
}

//+------------------------------------------------------------------+
void OpenSellOrder(double slPrice)
{
   if (HasOpenPosition()) 
   {
      Print("Cannot open SELL: Position already exists");
      return;
   }

   double entryPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Normalize prices
   entryPrice = NormalizeDouble(entryPrice, _Digits);
   slPrice = NormalizeDouble(slPrice, _Digits);
   
   // Ensure SL is above entry for sell
   if(slPrice <= entryPrice)
   {
      slPrice = entryPrice + (10 * _Point);
      Print("SL adjusted to be above entry price");
   }

   MqlTradeRequest request={};
   MqlTradeResult result={};

   request.action = TRADE_ACTION_DEAL;
   request.magic = MagicNumber;
   request.symbol = _Symbol;
   request.volume = lotSize;
   request.price = entryPrice;
   request.sl = slPrice;
   request.tp = 0;
   request.deviation = Slippage;
   request.type = ORDER_TYPE_SELL;
   request.type_filling = ORDER_FILLING_FOK;
   request.comment = OrderComment;

   if(OrderSend(request, result))
   {
      Print("SELL order opened: Ticket=", result.order, " Price=", entryPrice, " SL=", slPrice);
      
      // Store ticket in the zone that triggered the trade
      for(int i = 0; i < zoneCount; i++)
      {
         if(zones[i].direction == 1 && zones[i].used && zones[i].ticket == 0)
         {
            zones[i].ticket = (int)result.order;
            break;
         }
      }
   }
   else
   {
      Print("Failed to open SELL order. Error: ", GetLastError());
   }
}
//+------------------------------------------------------------------+
bool TrailingParabolicSAR(string symbol, double &newSL)
{
   if(PositionsTotal()==0)
      return false;

   double sarBuffer[];
   ArraySetAsSeries(sarBuffer,true);

   if(CopyBuffer(sarHandle,0,1,1,sarBuffer)<1)
      return false;

   double sarValue = sarBuffer[0];

   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);

      if(!PositionSelectByTicket(ticket))
         continue;

      if(PositionGetInteger(POSITION_MAGIC)!=MagicNumber)
         continue;

      if(PositionGetString(POSITION_SYMBOL)!=symbol)
         continue;

      long type = PositionGetInteger(POSITION_TYPE);
      double currentSL = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);

      double bid = SymbolInfoDouble(symbol,SYMBOL_BID);
      double ask = SymbolInfoDouble(symbol,SYMBOL_ASK);

      if(type==POSITION_TYPE_BUY)
      {
         if(sarValue > currentSL && sarValue < bid)
         {
            newSL = sarValue;
         }
         else continue;
      }
      else if(type==POSITION_TYPE_SELL)
      {
         if((currentSL==0 || sarValue < currentSL) && sarValue > ask)
         {
            newSL = sarValue;
         }
         else continue;
      }

      MqlTradeRequest req={};
      MqlTradeResult  res={};

      req.action   = TRADE_ACTION_SLTP;
      req.position = ticket;
      req.symbol   = symbol;
      req.sl       = newSL;
      req.tp       = tp;

      if(OrderSend(req,res))
      {
         if(res.retcode==TRADE_RETCODE_DONE)
         {
            Print("Trailing updated to: ",newSL);
            return true;
         }
      }
   }

   return false;
}
