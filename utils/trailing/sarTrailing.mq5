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

      if(PositionGetInteger(POSITION_MAGIC)!=Expert_MagicNumber)
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