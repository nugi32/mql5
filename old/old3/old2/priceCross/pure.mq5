    //+------------------------------------------------------------------+
    //|              EMA Crossover EA + BB Sideways Filter               |
    //+------------------------------------------------------------------+
    #property strict
    #property version   "1.30"

    //================ INPUT =================
    input group "=== EMA Settings (Entry TF) ==="
    input int EMA_period = 10;

    input group "=== Trailing Stops Settings ==="
    input double Trailing_RR_Distance = 1.0; // SL distance = 1R
    input double Trailing_RR_Step     = 0.5; // step (unused, ready for upgrade)

    input group "=== Bollinger Bands Settings ==="
    input int band_period = 14;
    input int band_shift = 0;
    input double standart_deviation = 2.0;
    input int band_range_sideways_definition = 5;

    input group "=== Trading Settings ==="
    input double Risk_Percent = 1.0;

    input group "=== Other Settings ==="
    input int    Magic_Number = 12345;
    input string Trade_Comment = "EMA-Cross-BB";

    //================ GLOBAL =================
    int emaHandle, bolingerBandHandle;

    double ema[];
    double bbUpper[], bbMiddle[], bbLower[];
    MqlRates rates[];

    //+------------------------------------------------------------------+
    int OnInit()
    {
    emaHandle = iMA(_Symbol,_Period,EMA_period,0,MODE_EMA,PRICE_CLOSE);
    bolingerBandHandle = iBands(_Symbol,_Period,band_period,band_shift,standart_deviation,PRICE_CLOSE);

    if(emaHandle==INVALID_HANDLE || bolingerBandHandle==INVALID_HANDLE)
        return INIT_FAILED;

    ArraySetAsSeries(ema,true);
    ArraySetAsSeries(bbUpper,true);
    ArraySetAsSeries(bbMiddle,true);
    ArraySetAsSeries(bbLower,true);
    ArraySetAsSeries(rates,true);

    return INIT_SUCCEEDED;
    }
    //+------------------------------------------------------------------+
    void OnDeinit(const int reason)
    {
    IndicatorRelease(emaHandle);
    IndicatorRelease(bolingerBandHandle);
    }
    //+------------------------------------------------------------------+
    void OnTick()
    {
    if(CopyRates(_Symbol,_Period,0,10,rates) < 10) return;
    if(CopyBuffer(emaHandle,0,0,10,ema) < 10) return;

    if(CopyBuffer(bolingerBandHandle,0,0,band_range_sideways_definition+2,bbUpper) <= 0) return;
    if(CopyBuffer(bolingerBandHandle,1,0,band_range_sideways_definition+2,bbMiddle) <= 0) return;
    if(CopyBuffer(bolingerBandHandle,2,0,band_range_sideways_definition+2,bbLower) <= 0) return;

    CheckForEntry();
    ManagePositions();
    checkForBounce();
    }
    //+------------------------------------------------------------------+
    bool isSideways()
    {
    double totalWidth = 0;

    for(int i=1; i<=band_range_sideways_definition; i++)
    {
        double width = bbUpper[i] - bbLower[i];
        totalWidth += width;
    }

    double avgWidth = totalWidth / band_range_sideways_definition;

    // threshold = 0.3% harga
    double price = rates[1].close;
    double threshold = price * 0.003;

    return (avgWidth < threshold);
    }

    bool crossUp () {

    double price_now  = rates[1].close;
    double price_prev = rates[2].close;

    double ema_now  = ema[1];
    double ema_prev = ema[2];

        return (price_prev <= ema_prev && price_now > ema_now);
    }
    bool crossDown () {

    double price_now  = rates[1].close;
    double price_prev = rates[2].close;

    double ema_now  = ema[1];
    double ema_prev = ema[2];

        return (price_prev >= ema_prev && price_now < ema_now);
    }
    //+------------------------------------------------------------------+
    void CheckForEntry()
    {
    if(HasOpenPosition()) return;
    //if(isSideways()) return;

    double price_now  = rates[1].close;
    double price_prev = rates[2].close;

    double ema_now  = ema[1];
    double ema_prev = ema[2];

    bool touchUp   = (rates[1].low  <= ema_now && rates[1].close > ema_now);
    bool touchDown = (rates[1].high >= ema_now && rates[1].close < ema_now);

    if(crossUp() || touchUp)
        OpenBuy();

    if(crossDown() || touchDown)
        OpenSell();
    }

    void checkForBounce () {
        //if(HasOpenPosition()) return;
        //if(isSideways()) return;

    double price_now  = rates[1].close;
    double price_prev = rates[2].close;

    double ema_now  = ema[1];
    double ema_prev = ema[2];

    bool touchUp   = (rates[1].low  <= ema_now && rates[1].close > ema_now);
    bool touchDown = (rates[1].high >= ema_now && rates[1].close < ema_now);
/*

    if(touchUp)
        OpenBuy();

    if(touchDown)
        OpenSell();*/
    }

    //+------------------------------------------------------------------+
    void ClosePosition(ulong ticket)
    {
    long type = PositionGetInteger(POSITION_TYPE);
    double volume = PositionGetDouble(POSITION_VOLUME);

    MqlTradeRequest req;
    MqlTradeResult  res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action   = TRADE_ACTION_DEAL;
    req.position = ticket;
    req.symbol   = _Symbol;
    req.volume   = volume;
    req.magic    = Magic_Number;
    req.deviation= 10;

    if(type==POSITION_TYPE_BUY)
    {
        req.type  = ORDER_TYPE_SELL;
        req.price = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    }
    else
    {
        req.type  = ORDER_TYPE_BUY;
        req.price = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    }

    OrderSend(req,res);
    }

    //+------------------------------------------------------------------+
    void ManageReverseTP(ulong ticket)
    {
    long type = PositionGetInteger(POSITION_TYPE);

    if(type==POSITION_TYPE_BUY &&
        crossDown())
        ClosePosition(ticket);

    if(type==POSITION_TYPE_SELL &&
        crossUp())
        ClosePosition(ticket);
    }
    //+------------------------------------------------------------------+
    bool HasOpenPosition()
    {
    for(int i=0;i<PositionsTotal();i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
                PositionGetString(POSITION_SYMBOL)==_Symbol)
                return true;
        }
    }
    return false;
    }
    //+------------------------------------------------------------------+
    void OpenBuy()
    {
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    double sl    = ema[1];

    if(!IsValidStop(entry,sl)) return;

    double lot = CalculateLot(entry,sl);
    if(lot<=0) return;

    SendOrder(ORDER_TYPE_BUY,lot,entry,sl,0);
    }
    //+------------------------------------------------------------------+
    void OpenSell()
    {
    double entry = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    double sl    = ema[1];

    if(!IsValidStop(sl,entry)) return;

    double lot = CalculateLot(sl,entry);
    if(lot<=0) return;

    SendOrder(ORDER_TYPE_SELL,lot,entry,sl,0);
    }
    //+------------------------------------------------------------------+
    bool IsValidStop(double price,double sl)
    {
    double stopLevel = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
    return MathAbs(price-sl) >= stopLevel;
    }
    //+------------------------------------------------------------------+
    double CalculateLot(double entry,double sl)
    {
    double riskMoney = AccountInfoDouble(ACCOUNT_EQUITY) * Risk_Percent / 100.0;
    double slDistance = MathAbs(entry - sl);
    if(slDistance<=0) return 0;

    double tickSize  = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
    if(tickSize<=0 || tickValue<=0) return 0;

    double lossPerLot = (slDistance / tickSize) * tickValue;
    double rawLot = riskMoney / lossPerLot;

    double minLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
    double maxLot  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
    double stepLot = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

    if(rawLot < minLot) return 0;

    double lot = MathFloor(rawLot / stepLot) * stepLot;
    lot = MathMax(lot,minLot);
    lot = MathMin(lot,maxLot);

    return NormalizeDouble(lot,2);
    }
    //+------------------------------------------------------------------+
    void SendOrder(ENUM_ORDER_TYPE type,double lot,double price,double sl,double tp)
    {
    MqlTradeRequest req;
    MqlTradeResult  res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action   = TRADE_ACTION_DEAL;
    req.symbol   = _Symbol;
    req.type     = type;
    req.volume   = lot;
    req.price    = price;
    req.sl       = sl;
    req.tp       = tp;
    req.magic    = Magic_Number;
    req.comment  = Trade_Comment + "|SL=" + DoubleToString(sl,_Digits);
    req.deviation= 10;

    OrderSend(req,res);
    }
    //+------------------------------------------------------------------+
    void ManagePositions()
    {
    for(int i=0;i<PositionsTotal();i++)
    {
        ulong ticket = PositionGetTicket(i);
        if(PositionSelectByTicket(ticket))
        {
            if(PositionGetInteger(POSITION_MAGIC)==Magic_Number &&
                PositionGetString(POSITION_SYMBOL)==_Symbol) {
                ManageReverseTP(ticket);
                } 
        } 
    }
    }
    //+------------------------------------------------------------------+
    void ModifySL(ulong ticket,double newSL)
    {
    MqlTradeRequest req;
    MqlTradeResult  res;
    ZeroMemory(req);
    ZeroMemory(res);

    req.action   = TRADE_ACTION_SLTP;
    req.position = ticket;
    req.symbol   = _Symbol;
    req.sl       = newSL;
    req.tp       = PositionGetDouble(POSITION_TP);

    OrderSend(req,res);
    }
    //+------------------------------------------------------------------+