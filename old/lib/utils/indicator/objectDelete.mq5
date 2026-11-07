//+------------------------------------------------------------------+
//|                    Delete All Chart Objects EA                   |
//+------------------------------------------------------------------+
#property strict

//---- input
input bool Delete_On_Init = true;     // Hapus saat EA dipasang
input bool Delete_Every_Tick = false; // Hapus setiap tick
input bool Delete_SubWindows = true;  // Hapus juga object di subwindow

//+------------------------------------------------------------------+
void DeleteAllObjects()
{
   long chart_id = ChartID();
   int total = ObjectsTotal(chart_id, -1, -1);

   for(int i = total - 1; i >= 0; i--)
   {
      string name = ObjectName(chart_id, i);
      if(name != "")
         ObjectDelete(chart_id, name);
   }

   if(Delete_SubWindows)
   {
      int windows = (int)ChartGetInteger(chart_id, CHART_WINDOWS_TOTAL);
      for(int w = 1; w < windows; w++)
      {
         int sub_total = ObjectsTotal(chart_id, w, -1);
         for(int j = sub_total - 1; j >= 0; j--)
         {
            string sub_name = ObjectName(chart_id, j, w);
            if(sub_name != "")
               ObjectDelete(chart_id, sub_name);
         }
      }
   }

   Print("Semua object berhasil dihapus.");
}
//+------------------------------------------------------------------+
int OnInit()
{
   if(Delete_On_Init)
      DeleteAllObjects();

   return(INIT_SUCCEEDED);
}
//+------------------------------------------------------------------+
void OnTick()
{
   if(Delete_Every_Tick)
      DeleteAllObjects();
}
//+------------------------------------------------------------------+