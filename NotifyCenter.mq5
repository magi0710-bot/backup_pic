//+------------------------------------------------------------------+
//|                                             NotifyCenter.mq5     |
//|  通知中心 EA                                                       |
//|  功能：                                                            |
//|   1. 圖表介面直接新增/刪除價格警報                                    |
//|   2. 掃描所有 EA 透過 NotifyHelper 新增的警報                        |
//|   3. 到價時統一發送推送通知（一次性）                                  |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.00"
#property strict

#include <NotifyHelper.mqh>

//--- 輸入參數
input int    ScanIntervalMS  = 500;    // 掃描間隔（毫秒）
input bool   ShowAlertList   = true;   // 是否在圖表顯示警報清單
input int    ListX           = 20;     // 清單顯示 X 位置
input int    ListY           = 50;     // 清單顯示 Y 位置

//--- 圖表 UI 物件名稱
#define OBJ_PANEL_BG      "NC_PanelBG"
#define OBJ_TITLE         "NC_Title"
#define OBJ_INPUT_PRICE   "NC_InputPrice"
#define OBJ_INPUT_MSG     "NC_InputMsg"
#define OBJ_BTN_ADD       "NC_BtnAdd"
#define OBJ_STATUS        "NC_Status"
#define OBJ_LIST_PREFIX   "NC_List_"

//--- UI 輸入暫存
string g_inputPrice  = "";
string g_inputMsg    = "";

//+------------------------------------------------------------------+
//| 初始化                                                             |
//+------------------------------------------------------------------+
int OnInit()
{
   EventSetMillisecondTimer(ScanIntervalMS);
   CreateUI();
   RefreshAlertList();
   Print("NotifyCenter 啟動完成，掃描間隔：", ScanIntervalMS, "ms");
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 移除                                                              |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   EventKillTimer();
   DeleteUI();
}

//+------------------------------------------------------------------+
//| Timer：掃描所有警報                                                 |
//+------------------------------------------------------------------+
void OnTimer()
{
   bool listChanged = false;

   for(int i = 1; i <= ALERT_MAX_ID; i++)
   {
      string keyActive = ALERT_PREFIX + IntegerToString(i) + "_Active";
      if(!GlobalVariableCheck(keyActive)) continue;

      int active = (int)GlobalVariableGet(keyActive);
      if(active != 1) continue;

      // 讀取警報資料
      double targetPrice = GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Price");
      int    above       = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Above");
      string symbol      = ReadAlertSymbol(i);
      string message     = ReadAlertMessage(i);

      if(StringLen(symbol) == 0) continue;

      // 取得當前價格
      double currentBid = SymbolInfoDouble(symbol, SYMBOL_BID);
      double currentAsk = SymbolInfoDouble(symbol, SYMBOL_ASK);
      if(currentBid == 0) continue;

      // 判斷是否觸發
      bool triggered = false;
      if(above == 1 && currentAsk >= targetPrice) triggered = true;
      if(above == 0 && currentBid <= targetPrice) triggered = true;

      if(triggered)
      {
         // 發送推送通知
         string notify = message + " | " + symbol +
                         " 當前價：" + DoubleToString(currentBid, _Digits);

         if(!SendNotification(notify))
            Print("NotifyCenter: 推送失敗 ID=", i, " 錯誤碼=", GetLastError());
         else
            Print("NotifyCenter: 推送成功 ID=", i, " → ", notify);

         // 一次性：標記為已觸發並清除
         GlobalVariableSet(keyActive, 0);
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_Price");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_Above");
         GlobalVariableDel(keyActive);
         DeleteAlertFiles(i);

         listChanged = true;

         // 圖表彈出提示
         SetStatus("✓ 警報觸發：" + symbol + " " + DoubleToString(targetPrice, _Digits));
      }
   }

   if(listChanged && ShowAlertList)
      RefreshAlertList();
}

//+------------------------------------------------------------------+
//| 圖表事件（按鈕點擊、輸入框）                                          |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   //--- 按鈕點擊
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      // 新增警報按鈕
      if(sparam == OBJ_BTN_ADD)
      {
         HandleAddAlert();
         // 重置按鈕狀態
         ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_STATE, false);
         return;
      }

      // 刪除警報按鈕（清單項目）
      if(StringFind(sparam, OBJ_LIST_PREFIX + "Del_") == 0)
      {
         string idStr = StringSubstr(sparam, StringLen(OBJ_LIST_PREFIX + "Del_"));
         int alertID  = (int)StringToInteger(idStr);
         RemoveAlert(alertID);
         DeleteAlertFiles(alertID);
         RefreshAlertList();
         SetStatus("已刪除警報 ID=" + IntegerToString(alertID));
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         return;
      }
   }

   //--- 輸入框結束編輯
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam == OBJ_INPUT_PRICE)
         g_inputPrice = ObjectGetString(0, OBJ_INPUT_PRICE, OBJPROP_TEXT);
      if(sparam == OBJ_INPUT_MSG)
         g_inputMsg = ObjectGetString(0, OBJ_INPUT_MSG, OBJPROP_TEXT);
   }
}

//+------------------------------------------------------------------+
//| 處理新增警報                                                        |
//+------------------------------------------------------------------+
void HandleAddAlert()
{
   g_inputPrice = ObjectGetString(0, OBJ_INPUT_PRICE, OBJPROP_TEXT);
   g_inputMsg   = ObjectGetString(0, OBJ_INPUT_MSG,   OBJPROP_TEXT);

   if(StringLen(g_inputPrice) == 0)
   {
      SetStatus("✗ 請輸入目標價格");
      return;
   }

   double price = StringToDouble(g_inputPrice);
   if(price <= 0)
   {
      SetStatus("✗ 價格格式錯誤");
      return;
   }

   int id = AddPriceAlert(Symbol(), price, g_inputMsg);
   if(id > 0)
   {
      SetStatus("✓ 已新增警報 ID=" + IntegerToString(id) +
                " | " + Symbol() + " @ " + DoubleToString(price, _Digits));
      // 清空輸入框
      ObjectSetString(0, OBJ_INPUT_PRICE, OBJPROP_TEXT, "");
      ObjectSetString(0, OBJ_INPUT_MSG,   OBJPROP_TEXT, "");
      g_inputPrice = "";
      g_inputMsg   = "";
      RefreshAlertList();
   }
   else
   {
      SetStatus("✗ 新增警報失敗");
   }
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 建立 UI                                                           |
//+------------------------------------------------------------------+
void CreateUI()
{
   int x = ListX;
   int y = ListY;
   int w = 340;

   // 背景面板
   CreatePanel(OBJ_PANEL_BG, x - 10, y - 10, w, 130, C'30,30,30', 180);

   // 標題
   CreateLabel(OBJ_TITLE, x, y, "📡 NotifyCenter 通知中心", clrGold, 10);

   // 價格輸入框
   CreateLabel("NC_LblPrice", x, y + 22, "目標價格：", clrSilver, 9);
   CreateEdit(OBJ_INPUT_PRICE, x + 70, y + 20, 120, 18, "");

   // 訊息輸入框
   CreateLabel("NC_LblMsg", x, y + 46, "自訂訊息：", clrSilver, 9);
   CreateEdit(OBJ_INPUT_MSG, x + 70, y + 44, 180, 18, "");

   // 新增按鈕
   CreateButton(OBJ_BTN_ADD, x, y + 70, 100, 22, "＋ 新增警報", clrWhite, C'0,120,60');

   // 狀態列
   CreateLabel(OBJ_STATUS, x, y + 100, "就緒", clrGray, 8);

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| 刷新警報清單                                                        |
//+------------------------------------------------------------------+
void RefreshAlertList()
{
   if(!ShowAlertList) return;

   // 先刪除舊清單物件
   for(int i = 1; i <= ALERT_MAX_ID; i++)
   {
      ObjectDelete(0, OBJ_LIST_PREFIX + "Row_"  + IntegerToString(i));
      ObjectDelete(0, OBJ_LIST_PREFIX + "Del_"  + IntegerToString(i));
      ObjectDelete(0, OBJ_LIST_PREFIX + "BG_"   + IntegerToString(i));
   }
   ObjectDelete(0, "NC_ListTitle");

   int x    = ListX;
   int yTop = ListY + 135;
   int row  = 0;

   CreateLabel("NC_ListTitle", x, yTop, "── 待觸發警報 ──", clrGray, 8);

   for(int i = 1; i <= ALERT_MAX_ID; i++)
   {
      string keyActive = ALERT_PREFIX + IntegerToString(i) + "_Active";
      if(!GlobalVariableCheck(keyActive)) continue;
      if((int)GlobalVariableGet(keyActive) != 1) continue;

      double price  = GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Price");
      int    above  = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Above");
      string symbol = ReadAlertSymbol(i);
      if(StringLen(symbol) == 0) continue;

      int rowY = yTop + 18 + row * 22;

      // 行背景
      CreatePanel(OBJ_LIST_PREFIX + "BG_" + IntegerToString(i),
                  x - 5, rowY - 2, 330, 20, C'45,45,45', 160);

      // 警報文字
      string dir  = (above == 1) ? "▲" : "▼";
      color  col  = (above == 1) ? clrLimeGreen : clrTomato;
      string text = "ID" + IntegerToString(i) + "  " + symbol +
                    "  " + dir + "  " + DoubleToString(price, _Digits);

      CreateLabel(OBJ_LIST_PREFIX + "Row_" + IntegerToString(i),
                  x, rowY, text, col, 9);

      // 刪除按鈕
      CreateButton(OBJ_LIST_PREFIX + "Del_" + IntegerToString(i),
                   x + 295, rowY - 2, 32, 18, "✕", clrWhite, C'140,30,30');

      row++;
   }

   if(row == 0)
      CreateLabel("NC_ListEmpty", x, yTop + 20, "（目前無待觸發警報）", clrGray, 8);
   else
      ObjectDelete(0, "NC_ListEmpty");

   ChartRedraw();
}

//+------------------------------------------------------------------+
//| UI 輔助函式                                                        |
//+------------------------------------------------------------------+
void SetStatus(string text)
{
   ObjectSetString(0, OBJ_STATUS, OBJPROP_TEXT, text);
   ChartRedraw();
}

void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,  x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,  y);
   ObjectSetInteger(0, name, OBJPROP_CORNER,      CORNER_LEFT_UPPER);
   ObjectSetString( 0, name, OBJPROP_TEXT,        text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,       clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,    fontSize);
   ObjectSetString( 0, name, OBJPROP_FONT,        "Arial");
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,  false);
}

void CreateEdit(string name, int x, int y, int w, int h, string defaultText)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetString( 0, name, OBJPROP_TEXT,         defaultText);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      C'50,50,50');
   ObjectSetInteger(0, name, OBJPROP_COLOR,        clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

void CreateButton(string name, int x, int y, int w, int h,
                  string text, color textClr, color bgClr)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetString( 0, name, OBJPROP_TEXT,         text);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        textClr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE,     9);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

void CreatePanel(string name, int x, int y, int w, int h, color bgClr, int alpha)
{
   ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE,   x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE,   y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,        w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,        h);
   ObjectSetInteger(0, name, OBJPROP_CORNER,       CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR,      bgClr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE,  BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_COLOR,        C'60,60,60');
   ObjectSetInteger(0, name, OBJPROP_BACK,         true);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE,   false);
}

void DeleteUI()
{
   ObjectsDeleteAll(0, "NC_");
   ObjectsDeleteAll(0, OBJ_LIST_PREFIX);
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| OnTick（必要，主邏輯在 Timer）                                       |
//+------------------------------------------------------------------+
void OnTick() {}
