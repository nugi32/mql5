//+------------------------------------------------------------------+
//|           Mean Reversion Intraday EA - Perbaikan Lengkap         |
//+------------------------------------------------------------------+
#property strict

input double LotSize      = 0.01;
input int SMA_Period      = 20;
input double ZScoreEntry  = 2.0;       // threshold entry
input int VolWindow       = 20;
input double VolThreshold = 0.001;     // low volatility filter
input int Slippage        = 3;
input int MagicNumber     = 12345;
input double SL_Factor    = 2.0;       // multiplier untuk std20

double CloseArray[];
double LogReturnArray[];
double std20_global;
double SMA20_global;

// proteksi entry sekali per candle
datetime last_entry_candle = 0;

//+------------------------------------------------------------------+
int OnInit()
{
    ArraySetAsSeries(CloseArray,true);
    ArraySetAsSeries(LogReturnArray,true);
    return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnTick()
{
    // pastikan ada cukup bar
    if(Bars(_Symbol,_Period) < SMA_Period + VolWindow + 2) return;

    // ambil harga close terakhir + candle sebelumnya untuk log return
    CopyClose(_Symbol,_Period,0,SMA_Period+VolWindow+2, CloseArray);

    //---- SMA dari candle terakhir
    double SMA20 = 0;
    for(int i=0; i<SMA_Period; i++)
        SMA20 += CloseArray[i];
    SMA20 /= SMA_Period;
    SMA20_global = SMA20;

    //---- StdDev dari candle terakhir
    double sum_dev = 0;
    for(int i=0; i<SMA_Period; i++)
        sum_dev += MathPow(CloseArray[i]-SMA20,2);
    double std20 = MathSqrt(sum_dev/SMA_Period);
    std20_global = std20;

    //---- Z-score dari candle terakhir
    double deviation = CloseArray[0] - SMA20;
    double z_score = deviation / std20;

    //---- Log return & rolling volatility
    ArrayResize(LogReturnArray, VolWindow);
    for(int i=0; i<VolWindow; i++)
        LogReturnArray[i] = MathLog(CloseArray[i]/CloseArray[i+1]);

    double mean_lr=0;
    for(int i=0;i<VolWindow;i++) mean_lr += LogReturnArray[i];
    mean_lr /= VolWindow;

    double sum_var=0;
    for(int i=0;i<VolWindow;i++) sum_var += MathPow(LogReturnArray[i]-mean_lr,2);
    double volatility = MathSqrt(sum_var/VolWindow);

    //---- Low volatility filter
    bool low_vol = (volatility < VolThreshold);

    //---- Entry: hanya sekali per candle
    datetime current_candle = iTime(_Symbol,_Period,0);
    if(current_candle == last_entry_candle) return;  // belum candle baru
    last_entry_candle = current_candle;

    if(low_vol && !HasOpenPosition())
    {
        if(z_score < -ZScoreEntry) OpenOrder(ORDER_TYPE_BUY, LotSize);
        if(z_score >  ZScoreEntry) OpenOrder(ORDER_TYPE_SELL, LotSize);
    }

    //---- Manage positions
    ManagePositions();
}

//+------------------------------------------------------------------+
void OpenOrder(ENUM_ORDER_TYPE type,double lots)
{
    double price = (type==ORDER_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_ASK)
                                         : SymbolInfoDouble(_Symbol,SYMBOL_BID);

    // TP & SL relatif ke entry price
    double tp = (type==ORDER_TYPE_BUY)? price + std20_global : price - std20_global;
    double sl = (type==ORDER_TYPE_BUY)? price - SL_Factor*std20_global : price + SL_Factor*std20_global;

    // minimal stop broker
    double stop_level = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;

    // pastikan SL valid
    if(MathAbs(price - sl) < stop_level)
        sl = (type==ORDER_TYPE_BUY)? price - stop_level : price + stop_level;

    // pastikan TP valid
    if(MathAbs(tp - price) < stop_level)
        tp = (type==ORDER_TYPE_BUY)? price + stop_level : price - stop_level;

    sl = NormalizeDouble(sl,_Digits);
    tp = NormalizeDouble(tp,_Digits);

    Print("Open ",EnumToString(type)," Price=",price," SL=",sl," TP=",tp," std20=",std20_global);

    MqlTradeRequest request;
    MqlTradeResult result;
    ZeroMemory(request);
    ZeroMemory(result);

    request.action    = TRADE_ACTION_DEAL;
    request.symbol    = _Symbol;
    request.volume    = lots;
    request.type      = type;
    request.price     = price;
    request.sl        = sl;
    request.tp        = tp;
    request.deviation = Slippage;
    request.magic     = MagicNumber;

    if(!OrderSend(request,result))
        Print("OrderSend failed, retcode=",result.retcode);
}

//+------------------------------------------------------------------+
void ManagePositions()
{
    int total = PositionsTotal();
    for(int j=0;j<total;j++)
    {
        ulong ticket = PositionGetTicket(j);
        if(!PositionSelectByTicket(ticket)) continue;

        string sym = PositionGetString(POSITION_SYMBOL);
        if(sym != _Symbol) continue;

        double pos_price = PositionGetDouble(POSITION_PRICE_OPEN);
        double volume    = PositionGetDouble(POSITION_VOLUME);
        int pos_type     = (int)PositionGetInteger(POSITION_TYPE);
        double price_now = (pos_type==POSITION_TYPE_BUY)? SymbolInfoDouble(_Symbol,SYMBOL_BID)
                                                        : SymbolInfoDouble(_Symbol,SYMBOL_ASK);

        double tp = (pos_type==POSITION_TYPE_BUY)? pos_price + std20_global : pos_price - std20_global;
        double sl = (pos_type==POSITION_TYPE_BUY)? pos_price - SL_Factor*std20_global : pos_price + SL_Factor*std20_global;

        double stop_level = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;

        if(MathAbs(price_now - sl) < stop_level) sl = (pos_type==POSITION_TYPE_BUY)? pos_price - stop_level : pos_price + stop_level;
        if(MathAbs(tp - pos_price) < stop_level) tp = (pos_type==POSITION_TYPE_BUY)? pos_price + stop_level : pos_price - stop_level;

        sl = NormalizeDouble(sl,_Digits);
        tp = NormalizeDouble(tp,_Digits);

        // Close jika kena SL/TP
        if((pos_type==POSITION_TYPE_BUY && (price_now>=tp || price_now<=sl)) ||
           (pos_type==POSITION_TYPE_SELL && (price_now<=tp || price_now>=sl)))
        {
            MqlTradeRequest request;
            MqlTradeResult result;
            ZeroMemory(request);
            ZeroMemory(result);

            request.action   = TRADE_ACTION_DEAL;
            request.position = ticket;
            request.symbol   = _Symbol;
            request.volume   = volume;
            request.type     = (pos_type==POSITION_TYPE_BUY)? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            request.price    = price_now;
            request.deviation= Slippage;
            request.magic    = MagicNumber;

            if(!OrderSend(request,result))
                Print("Close failed, retcode=",result.retcode);
            else
                Print("Position closed, ticket=",ticket);
        }
    }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i=0;i<PositionsTotal();i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         if(PositionGetInteger(POSITION_MAGIC)==MagicNumber &&
            PositionGetString(POSITION_SYMBOL)==_Symbol)
            return true;
      }
   }
   return false;
}
//+------------------------------------------------------------------+