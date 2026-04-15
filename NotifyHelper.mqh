//+------------------------------------------------------------------+
//|                                              NotifyHelper.mqh    |
//|  共用警報函式庫                                                     |
//|  使用方式：在其他 EA 頂部加入 #include <NotifyHelper.mqh>           |
//|  然後呼叫 AddPriceAlert() 新增價格警報                              |
//+------------------------------------------------------------------+
#ifndef NOTIFY_HELPER_MQH
#define NOTIFY_HELPER_MQH

#define ALERT_PREFIX     "ALERT_"
#define ALERT_MAX_ID     100        // 最多同時存在 100 個警報
#define GV_ALERT_COUNTER "ALERT_COUNTER"

//+------------------------------------------------------------------+
//| 新增價格警報                                                        |
//| symbol  : 商品名稱，例如 "EURUSD"，填 "" 則自動使用當前圖表商品        |
//| price   : 目標價格                                                  |
//| message : 自訂通知訊息，填 "" 則自動產生                              |
//| 回傳值  : 警報 ID（失敗回傳 -1）                                      |
//+------------------------------------------------------------------+
int AddPriceAlert(string symbol, double price, string message = "")
{
   // 商品名稱預設為當前圖表
   if(StringLen(symbol) == 0)
      symbol = Symbol();

   // 自動產生訊息
   if(StringLen(message) == 0)
      message = symbol + " 到達價格 " + DoubleToString(price, _Digits);

   // 取得當前商品的 Ask/Bid 判斷方向
   double currentPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
   if(currentPrice == 0)
   {
      Print("NotifyHelper: 無法取得 ", symbol, " 的價格，請確認商品名稱");
      return -1;
   }

   // 判斷是向上突破還是向下跌破
   int above = (price > currentPrice) ? 1 : 0;

   // 找一個空閒的 ID
   int alertID = -1;
   for(int i = 1; i <= ALERT_MAX_ID; i++)
   {
      string keyActive = ALERT_PREFIX + IntegerToString(i) + "_Active";
      if(!GlobalVariableCheck(keyActive))
      {
         alertID = i;
         break;
      }
   }

   if(alertID == -1)
   {
      Print("NotifyHelper: 警報數量已達上限 (", ALERT_MAX_ID, ")，請清理舊警報");
      return -1;
   }

   // 寫入 GlobalVariable
   // 商品名稱用檔案存（GlobalVariable 不支援字串）
   WriteAlertSymbol(alertID, symbol);
   WriteAlertMessage(alertID, message);

   GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_Price",  price);
   GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_Above",  above);
   GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_Active", 1);

   Print("NotifyHelper: 警報已新增 ID=", alertID,
         " | 商品=", symbol,
         " | 目標價=", DoubleToString(price, _Digits),
         " | 方向=", (above == 1 ? "向上突破" : "向下跌破"));

   return alertID;
}

//+------------------------------------------------------------------+
//| 取消指定 ID 的警報                                                  |
//+------------------------------------------------------------------+
void RemoveAlert(int alertID)
{
   string prefix = ALERT_PREFIX + IntegerToString(alertID) + "_";
   GlobalVariableDel(prefix + "Price");
   GlobalVariableDel(prefix + "Above");
   GlobalVariableDel(prefix + "Active");
   Print("NotifyHelper: 警報 ID=", alertID, " 已取消");
}

//+------------------------------------------------------------------+
//| 內部：將商品名稱寫入檔案                                             |
//+------------------------------------------------------------------+
void WriteAlertSymbol(int id, string symbol)
{
   string fname = "AlertSymbol_" + IntegerToString(id) + ".txt";
   int h = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, symbol);
      FileClose(h);
   }
}

//+------------------------------------------------------------------+
//| 內部：讀取商品名稱                                                  |
//+------------------------------------------------------------------+
string ReadAlertSymbol(int id)
{
   string fname = "AlertSymbol_" + IntegerToString(id) + ".txt";
   int h = FileOpen(fname, FILE_READ | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE) return "";
   string s = FileReadString(h);
   FileClose(h);
   return s;
}

//+------------------------------------------------------------------+
//| 內部：將訊息寫入檔案                                                |
//+------------------------------------------------------------------+
void WriteAlertMessage(int id, string message)
{
   string fname = "AlertMessage_" + IntegerToString(id) + ".txt";
   int h = FileOpen(fname, FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h != INVALID_HANDLE)
   {
      FileWriteString(h, message);
      FileClose(h);
   }
}

//+------------------------------------------------------------------+
//| 內部：讀取訊息                                                      |
//+------------------------------------------------------------------+
string ReadAlertMessage(int id)
{
   string fname = "AlertMessage_" + IntegerToString(id) + ".txt";
   int h = FileOpen(fname, FILE_READ | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE) return "";
   string s = FileReadString(h);
   FileClose(h);
   return s;
}

//+------------------------------------------------------------------+
//| 內部：清除檔案                                                      |
//+------------------------------------------------------------------+
void DeleteAlertFiles(int id)
{
   FileDelete("AlertSymbol_"  + IntegerToString(id) + ".txt", FILE_COMMON);
   FileDelete("AlertMessage_" + IntegerToString(id) + ".txt", FILE_COMMON);
}

#endif
