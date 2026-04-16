//+------------------------------------------------------------------+
//|                                     NotifySync_Final_Fixed.mq5   |
//+------------------------------------------------------------------+
#property copyright "Custom EA"
#property version   "1.51"
#property strict

#include <NotifyHelper.mqh>

//--- 輸入參數
input group "── 通知中心設置 ──"
input bool   ShowUIPanel     = true;     // 顯示警報面板
input int    ScanIntervalMS  = 500;
input bool   ShowAlertList   = true;     // 顯示警報列表(結合於主面板下方)
input bool   ShowAllSymbolsAlerts = true; // 列表顯示所有商品(否則僅顯示當前圖表)
input int    ListX           = 20;
input int    ListY           = 50;

input group "── 獨立警報清單視窗 ──"
input bool   ShowAlertWindow  = true;     // 啟用獨立警報視窗 (可上下翻頁)
input int    AlertWinX        = 250;      // 獨立視窗 X 坐標
input int    AlertWinY        = 50;       // 獨立視窗 Y 坐標
input int    MaxAlertsPerPage = 10;       // 每頁顯示幾筆警報

/*
input group "── 多視窗同步設置 ──"
input int    SyncBtnX      = 200; // 同步按鈕 X 座標
input int    SyncBtnY      = 50;  // 同步按鈕 Y 座標
input bool   EnableCrosshairSync = false;  // 啟用十字光標同步 (目前已於程式碼禁用)
input int    WindowIndex   = 0;
input ENUM_TIMEFRAMES TF0 = PERIOD_M15;
input ENUM_TIMEFRAMES TF1 = PERIOD_H1;
input ENUM_TIMEFRAMES TF2 = PERIOD_H4;
input ENUM_TIMEFRAMES TF3 = PERIOD_D1;
input ENUM_TIMEFRAMES TF4 = PERIOD_W1;
input ENUM_TIMEFRAMES TF5 = PERIOD_MN1;
*/

input group "── 指標警報設置 ──"
input bool   EnableEMA   = true;     // 顯示 EMA 按鈕 1
input int    EMAPeriod   = 50;       // EMA 1 參數
input bool   EnableEMA2  = true;     // 顯示 EMA 按鈕 2
input int    EMAPeriod2  = 20;       // EMA 2 參數
input bool   EnableBB    = true;     // 顯示布林通道按鈕
input int    BBPeriod    = 5;        // 布林通道參數 (MA)
input double BBDeviation = 1.0;      // 布林通道標準差

//--- 定義常量
#define OBJ_PANEL_BG      "NC_PanelBG"
#define OBJ_INPUT_PRICE   "NC_InputPrice"
#define OBJ_INPUT_MSG     "NC_InputMsg"
#define OBJ_BTN_ADD       "NC_BtnAdd"
#define OBJ_STATUS        "NC_Status"
#define OBJ_LIST_PREFIX   "NC_List_"
#define BUTTON_SYNC       "btn_sync_all"

//--- 全域變數
string   g_lastSymbol    = "";
datetime g_lastTimestamp = 0;
datetime g_lastResetTS   = 0;
bool     g_isSwitching   = false;
bool     g_isPickingPrice = false;
bool     g_isMinimized    = false;
int      g_listPage       = 0;  // 記錄目前警報列表分頁

//+------------------------------------------------------------------+
//| 初始化                                                           |
//+------------------------------------------------------------------+
int OnInit()
{
   // if(WindowIndex < 0 || WindowIndex > 5) return INIT_PARAMETERS_INCORRECT;
   EventSetMillisecondTimer(ScanIntervalMS);
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true); // 啟用滑鼠移動事件，供右鍵取價使用
   
   if(ShowUIPanel) CreateNCUI();
   RefreshAlertList();
   // CreateSyncButton();
   
   g_lastSymbol = Symbol();
   // g_lastTimestamp = (datetime)GlobalVariableGet("MultiTF_Timestamp");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| 反初始化                                                         |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) 
{ 
   EventKillTimer(); 
   ObjectsDeleteAll(0, "NC_"); 
   ObjectDelete(0, BUTTON_SYNC); 
   ObjectDelete(0, "SyncCrossV");
   ObjectDelete(0, "SyncCrossH");
}

//+------------------------------------------------------------------+
//| 定時器事件                                                       |
//+------------------------------------------------------------------+
void OnTimer() 
{ 
   CheckAlerts(); 
   // CheckSync();
}

//+------------------------------------------------------------------+
//| 圖表事件處理 (十字光標取價與確認訊息)                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   /* --- 十字光標同步邏輯已禁用 ---
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      // ... (代碼省略)
   }
   */

   /*
   if(id == CHARTEVENT_CUSTOM + 1002 && EnableCrosshairSync) {
      if(!ObjectCreate(0, "SyncCrossV", OBJ_VLINE, 0, (datetime)lparam, 0)) ObjectMove(0, "SyncCrossV", 0, (datetime)lparam, 0);
      ObjectSetInteger(0, "SyncCrossV", OBJPROP_COLOR, clrSilver); ObjectSetInteger(0, "SyncCrossV", OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(0, "SyncCrossV", OBJPROP_BACK, true); ObjectSetInteger(0, "SyncCrossV", OBJPROP_SELECTABLE, false);
      if(!ObjectCreate(0, "SyncCrossH", OBJ_HLINE, 0, 0, dparam)) ObjectMove(0, "SyncCrossH", 0, 0, dparam);
      ObjectSetInteger(0, "SyncCrossH", OBJPROP_COLOR, clrSilver); ObjectSetInteger(0, "SyncCrossH", OBJPROP_STYLE, STYLE_DOT); ObjectSetInteger(0, "SyncCrossH", OBJPROP_BACK, true); ObjectSetInteger(0, "SyncCrossH", OBJPROP_SELECTABLE, false);
      ChartRedraw();
   }
   if(id == CHARTEVENT_CUSTOM + 1003) {
      ObjectDelete(0, "SyncCrossV"); ObjectDelete(0, "SyncCrossH"); ChartRedraw();
   }
   */

   // 1. 取價模式：監聽滑鼠移動事件，偵測右鍵按下 (dparam bit1 = 0x0002)
   if(g_isPickingPrice && id == CHARTEVENT_MOUSE_MOVE)
   {
      // MQL5 中 CHARTEVENT_MOUSE_MOVE 的參數：lparam(X), dparam(Y), sparam(按鍵狀態字串)
      int mouseKeys = (int)StringToInteger(sparam);
      if((mouseKeys & 2) == 2)   // 右鍵按下
      {
         int x = (int)lparam;        // 滑鼠X像素座標
         int y = (int)dparam;        // 滑鼠Y像素座標
         datetime dt;
         double   pickedPrice;
         int      sub_win = 0;

         if(ChartXYToTimePrice(0, x, y, sub_win, dt, pickedPrice))
         {
            pickedPrice = NormalizeDouble(pickedPrice, _Digits);
            ObjectSetString(0, OBJ_INPUT_PRICE, OBJPROP_TEXT, DoubleToString(pickedPrice, _Digits));
            
            string msg = ObjectGetString(0, OBJ_INPUT_MSG, OBJPROP_TEXT);
            if(msg == "" || msg == "警報訊息...") msg = GetTfString() + "取價";

            // 跳出彈窗確認
            string confirmStr = "確定要在以下位置新增警報嗎？\n\n商品：" + Symbol() + "\n價格：" + DoubleToString(pickedPrice, _Digits) + "\n訊息：" + msg;
            int res = MessageBox(confirmStr, "警報確認", MB_YESNO | MB_ICONQUESTION);

            if(res == IDYES)
            {
               int alertID = AddPriceAlert(Symbol(), pickedPrice, msg);
               if(alertID > 0) {
                  SetStatus("✓ 已新增警報 ID=" + IntegerToString(alertID));
                  RefreshAlertList();
               }
            }
            else {
               SetStatus("已取消新增");
            }
         }
         
         // 完成後自動恢復
         g_isPickingPrice = false;
         ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_BGCOLOR, C'0,120,60');
         ChartSetInteger(0, CHART_CROSSHAIR_TOOL, false); 
         return;
      }
   }

   // 2. 處理按鈕點擊
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "NC_BtnMin")
      {
         g_isMinimized = !g_isMinimized;
         UpdateUIVisibility();
         ObjectSetInteger(0, "NC_BtnMin", OBJPROP_STATE, false);
      }

      if(sparam == OBJ_BTN_ADD)
      {
         g_isPickingPrice = !g_isPickingPrice;
         if(g_isPickingPrice) {
            SetStatus(">>>> 移動十字游標定位，按右鍵確認 <<<<");
            ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_BGCOLOR, clrOrange);
            ChartSetInteger(0, CHART_CROSSHAIR_TOOL, true); // 自動啟動十字光標
         } else {
            SetStatus("就緒");
            ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_BGCOLOR, C'0,120,60');
            ChartSetInteger(0, CHART_CROSSHAIR_TOOL, false);
         }
         ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_STATE, false);
      }

      if(sparam == "NC_BtnEMA" || sparam == "NC_BtnEMA2")
      {
         int p_ema = (sparam == "NC_BtnEMA") ? EMAPeriod : EMAPeriod2;
         string emaName = IntegerToString(p_ema) + " EMA";
         int res = MessageBox("確定要在當前圖表新增追蹤 " + emaName + " 的動態警報嗎？", emaName + " 警報確認", MB_YESNO | MB_ICONQUESTION);
         if(res == IDYES) {
            int handle = GetCachedEMAHandle(Symbol(), Period(), p_ema);
            double emaBuf[1];
            if(handle != INVALID_HANDLE && CopyBuffer(handle, 0, 0, 1, emaBuf) > 0) {
               double currentEma = NormalizeDouble(emaBuf[0], _Digits);
               string finalMsg = GetTfString() + IntegerToString(p_ema) + "ema";
               int alertID = AddPriceAlert(Symbol(), currentEma, finalMsg);
               if(alertID > 0) {
                  GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_TYPE", 1);
                  GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_P", p_ema);
                  GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_TF", Period());
                  SetStatus("✓ 已新增 " + finalMsg + " 警報 ID=" + IntegerToString(alertID));
                  RefreshAlertList();
               }
            } else {
               SetStatus("無法獲獲 EMA 數據");
            }
         }
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }

      if(sparam == "NC_BtnBBH" || sparam == "NC_BtnBBL")
      {
         bool isBBH = (sparam == "NC_BtnBBH");
         string modeName = isBBH ? "BBH" : "BBL";
         int res = MessageBox("確定要在當前圖表新增追蹤 " + modeName + " 的動態警報嗎？", modeName + " 警報確認", MB_YESNO | MB_ICONQUESTION);
         if(res == IDYES) {
            int handle = GetCachedBandsHandle(Symbol(), Period());
            double bbBuf[1];
            int bufferNum = isBBH ? UPPER_BAND : LOWER_BAND;
            if(handle != INVALID_HANDLE && CopyBuffer(handle, bufferNum, 0, 1, bbBuf) > 0) {
               double currentBB = NormalizeDouble(bbBuf[0], _Digits);
               string finalMsg = GetTfString() + modeName;
               int alertID = AddPriceAlert(Symbol(), currentBB, finalMsg);
               if(alertID > 0) {
                  GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_BB", isBBH ? 1 : 2);
                  GlobalVariableSet(ALERT_PREFIX + IntegerToString(alertID) + "_IND_TF", Period());
                  SetStatus("✓ 已新增 " + finalMsg + " 警報 ID=" + IntegerToString(alertID));
                  RefreshAlertList();
               }
            } else {
               SetStatus("無法獲取 BB 數據");
            }
         }
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }

      if(StringFind(sparam, OBJ_LIST_PREFIX + "Del_") == 0)
      {
         int alertID = (int)StringToInteger(StringSubstr(sparam, StringLen(OBJ_LIST_PREFIX + "Del_")));
         RemoveAlert(alertID);
         DeleteAlertFiles(alertID);
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_EMA50");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_TYPE");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_P");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_EMA_TF");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_BB");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(alertID) + "_IND_TF");
         RefreshAlertList();
      }

      if(sparam == "NC_AL_BtnUp") {
         if(g_listPage > 0) {
            g_listPage--;
            RefreshAlertList();
         }
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }
      if(sparam == "NC_AL_BtnDn") {
         g_listPage++;
         RefreshAlertList();
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      }


/*
      if(sparam == BUTTON_SYNC)
      {
         ForceSyncAndReset();
         ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_STATE, false);
      }
*/
   }
}

//+------------------------------------------------------------------+
//| 核心功能函式區                                                   |
//+------------------------------------------------------------------+
int GetCachedBandsHandle(string sym, ENUM_TIMEFRAMES tf) {
   static int handles[6] = {INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
   static ENUM_TIMEFRAMES tfs[6] = {0};
   static string syms[6] = {""};
   for(int i=0; i<6; i++) {
      if(handles[i] != INVALID_HANDLE && tfs[i] == tf && syms[i] == sym)
         return handles[i];
   }
   for(int i=0; i<6; i++) {
      if(handles[i] == INVALID_HANDLE || syms[i] != sym) {
         if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
         // 布林通道參數
         handles[i] = iBands(sym, tf, BBPeriod, 0, BBDeviation, PRICE_CLOSE);
         tfs[i] = tf; syms[i] = sym;
         return handles[i];
      }
   }
   return INVALID_HANDLE;
}

int GetCachedEMAHandle(string sym, ENUM_TIMEFRAMES tf, int period) {
   static int handles[10] = {INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE,INVALID_HANDLE};
   static ENUM_TIMEFRAMES tfs[10] = {0};
   static string syms[10] = {""};
   static int periods[10] = {0};
   for(int i=0; i<10; i++) {
      if(handles[i] != INVALID_HANDLE && tfs[i] == tf && syms[i] == sym && periods[i] == period)
         return handles[i];
   }
   for(int i=0; i<10; i++) {
      if(handles[i] == INVALID_HANDLE || (syms[i] != sym && i>=9)) { 
         if(handles[i] != INVALID_HANDLE) IndicatorRelease(handles[i]);
         handles[i] = iMA(sym, tf, period, 0, MODE_EMA, PRICE_CLOSE);
         tfs[i] = tf; syms[i] = sym; periods[i] = period;
         return handles[i];
      }
   }
   return INVALID_HANDLE;
}

string GetTfString(ENUM_TIMEFRAMES tf = PERIOD_CURRENT) {
   if(tf == PERIOD_CURRENT) tf = Period();
   if(tf == PERIOD_M1) return "1m";
   if(tf == PERIOD_M5) return "5m";
   if(tf == PERIOD_M15) return "15m";
   if(tf == PERIOD_M30) return "30m";
   if(tf == PERIOD_H1) return "1h";
   if(tf == PERIOD_H4) return "4h";
   if(tf == PERIOD_D1) return "1d";
   if(tf == PERIOD_W1) return "1w";
   if(tf == PERIOD_MN1) return "MN";
   return IntegerToString(tf);
}

void CheckAlerts()
{
   bool changed = false;
   bool emaUpdated = false;
   for(int i = 1; i <= ALERT_MAX_ID; i++) {
      string key = ALERT_PREFIX + IntegerToString(i) + "_Active";
      if(!GlobalVariableCheck(key) || (int)GlobalVariableGet(key) != 1) continue;
      double tp = GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Price");
      string sym = ReadAlertSymbol(i);
      if(sym == "") continue; // 避免檔案鎖定時讀到空字串，導致誤判
      int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(symDigits <= 0) symDigits = 5; // 防禦：如果載入中取不到位數，給個稍微正常的預設值
      
      // 動態更新 EMA 價格
      string emaTypeKey = ALERT_PREFIX + IntegerToString(i) + "_EMA_TYPE";
      string emaOldKey  = ALERT_PREFIX + IntegerToString(i) + "_EMA50";
      string bbKey      = ALERT_PREFIX + IntegerToString(i) + "_BB";
      bool isDynamicAlert = false;
      int tftf = 0;
      
      if((GlobalVariableCheck(emaTypeKey) && GlobalVariableGet(emaTypeKey) == 1) || (GlobalVariableCheck(emaOldKey) && GlobalVariableGet(emaOldKey) == 1)) {
         tftf = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_TF");
         int p_ema = GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_EMA_P") ? (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_P") : 50; 
         isDynamicAlert = true;
         // 只讓正確週期的視窗負責更新 EMA
         if(tftf == Period()) {
            int hMA = GetCachedEMAHandle(ReadAlertSymbol(i), (ENUM_TIMEFRAMES)tftf, p_ema);
            if(hMA != INVALID_HANDLE) {
               double emaBuf[1];
               if(CopyBuffer(hMA, 0, 0, 1, emaBuf) > 0) {
                  if(emaBuf[0] > 0 && emaBuf[0] != EMPTY_VALUE) {
                     double newTp = NormalizeDouble(emaBuf[0], symDigits);
                     if(newTp != tp) { // 只有價格真正變動才觸發刷新
                        tp = newTp;
                        GlobalVariableSet(ALERT_PREFIX + IntegerToString(i) + "_Price", tp);
                        emaUpdated = true;
                     }
                  }
               }
            }
         }
      } else if(GlobalVariableCheck(bbKey)) {
         int bbMode = (int)GlobalVariableGet(bbKey);
         tftf = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_IND_TF");
         isDynamicAlert = true;
         if(tftf == Period()) {
            int hBB = GetCachedBandsHandle(ReadAlertSymbol(i), (ENUM_TIMEFRAMES)tftf);
            if(hBB != INVALID_HANDLE) {
               double bbBuf[1];
               int bufferNum = (bbMode == 1) ? UPPER_BAND : LOWER_BAND;
               if(CopyBuffer(hBB, bufferNum, 0, 1, bbBuf) > 0) {
                  if(bbBuf[0] > 0 && bbBuf[0] != EMPTY_VALUE) {
                     double newTp = NormalizeDouble(bbBuf[0], symDigits);
                     if(newTp != tp) {
                        tp = newTp;
                        GlobalVariableSet(ALERT_PREFIX + IntegerToString(i) + "_Price", tp);
                        emaUpdated = true;
                     }
                  }
               }
            }
         }
      }

      int ab = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Above");
      
      // 動態警報必須在專屬週期視窗觸發，以維持指標更新
      if(isDynamicAlert) {
         if(tftf != Period()) continue;
      } else {
         // 若是背景切換掉的商品，由當前商品自行檢測
         if(sym != Symbol()) continue;
      }

      double bid = SymbolInfoDouble(sym, SYMBOL_BID), ask = SymbolInfoDouble(sym, SYMBOL_ASK);
      if(bid <= 0 || ask <= 0) continue; // 防止背景商品未能取得報價時，價格為0導致的誤判
      if(tp <= 0 || tp == EMPTY_VALUE) continue; // 防禦：無效的 tp 價格不觸發

      if((ab == 1 && bid >= tp) || (ab == 0 && bid <= tp)) {
         SendNotification(ReadAlertMessage(i) + " | " + sym + " @" + DoubleToString(tp, symDigits));
         GlobalVariableDel(key); DeleteAlertFiles(i); changed = true;
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_EMA50");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_EMA_TF");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_BB");
         GlobalVariableDel(ALERT_PREFIX + IntegerToString(i) + "_IND_TF");
      }
   }
   if(changed || emaUpdated) RefreshAlertList();
}

/*
void CheckSync()
{
   if(g_isSwitching) return;
   string curSym = Symbol();
   if(curSym != g_lastSymbol) {
      g_isSwitching = true; datetime ts = TimeCurrent();
      GlobalVariableSet("MultiTF_ChangedBy", (double)WindowIndex);
      GlobalVariableSet("MultiTF_Timestamp", (double)ts);
      WriteSymbolToFile(curSym, ts); g_lastSymbol = curSym; g_lastTimestamp = ts;
      g_isSwitching = false; return;
   }
   datetime rTS = (datetime)GlobalVariableGet("MultiTF_Timestamp");
   datetime rRST = (datetime)GlobalVariableGet("MultiTF_ForceResetTS");
   if(rTS > g_lastTimestamp || rRST > g_lastResetTS) {
      if((int)GlobalVariableGet("MultiTF_ChangedBy") == WindowIndex) { g_lastTimestamp = rTS; g_lastResetTS = rRST; return; }
      string nS = ""; datetime fTS = 0;
      if(ReadSymbolFromFile(nS, fTS) && (fTS == rTS || rRST > g_lastResetTS)) {
         g_isSwitching = true;
         ChartSetSymbolPeriod(0, nS, (rRST > g_lastResetTS ? GetDefaultTF(WindowIndex) : PERIOD_CURRENT));
         g_lastSymbol = nS; g_lastTimestamp = rTS; g_lastResetTS = rRST;
         g_isSwitching = false;
      }
   }
}

void ForceSyncAndReset() {
   datetime ts = TimeCurrent(); 
   GlobalVariableSet("MultiTF_ForceResetTS", (double)ts);
   GlobalVariableSet("MultiTF_Timestamp", (double)ts);
   GlobalVariableSet("MultiTF_ChangedBy", (double)WindowIndex);
   WriteSymbolToFile(Symbol(), ts);
   ChartSetSymbolPeriod(0, Symbol(), GetDefaultTF(WindowIndex));
   g_lastTimestamp = ts;
   g_lastResetTS = ts;
}

ENUM_TIMEFRAMES GetDefaultTF(int idx) { if(idx==0) return TF0; if(idx==1) return TF1; if(idx==2) return TF2; if(idx==3) return TF3; if(idx==4) return TF4; if(idx==5) return TF5; return PERIOD_CURRENT; }

void WriteSymbolToFile(string s, datetime t) { int h=FileOpen("MultiTF_Sync.txt",FILE_WRITE|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE); if(h!=INVALID_HANDLE){FileWriteString(h,s+"\n"+IntegerToString(t));FileClose(h);}}

bool ReadSymbolFromFile(string &s, datetime &t) { int h=FileOpen("MultiTF_Sync.txt",FILE_READ|FILE_TXT|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE); if(h==INVALID_HANDLE)return false; s=FileReadString(h); t=(datetime)StringToInteger(FileReadString(h)); FileClose(h); return true; }
*/

//+------------------------------------------------------------------+
//| UI 繪製函式區                                                    |
//+------------------------------------------------------------------+
void CreateNCUI() {
   int x = ListX, y = ListY;
   CreatePanel("NC_BG", x-10, y-10, 170, 145, C'30,30,30');
   CreateLabel("NC_T", x, y, "📡 NotifySync Pro", clrGold, 10);
   CreateEdit(OBJ_INPUT_PRICE, x, y+20, 150, 20, "點擊取價");
   CreateEdit(OBJ_INPUT_MSG, x, y+45, 150, 20, "警報訊息...");
   CreateButton(OBJ_BTN_ADD, x, y+70, 48, 22, "取價", clrWhite, C'0,120,60');
   if(EnableEMA) CreateButton("NC_BtnEMA", x+51, y+70, 48, 22, IntegerToString(EMAPeriod)+"e", clrWhite, C'40,80,180');
   if(EnableEMA2) CreateButton("NC_BtnEMA2", x+102, y+70, 48, 22, IntegerToString(EMAPeriod2)+"e", clrWhite, C'70,120,200');
   if(EnableBB) {
      CreateButton("NC_BtnBBH", x, y+95, 73, 22, "📈 BBH", clrWhite, C'180,40,180');
      CreateButton("NC_BtnBBL", x+77, y+95, 73, 22, "📉 BBL", clrWhite, C'180,40,180');
   }
   CreateButton("NC_BtnMin", x+130, y-10, 20, 20, g_isMinimized ? "▼" : "▲", clrWhite, C'80,80,80');
   CreateLabel(OBJ_STATUS, x, y+120, "就緒", clrGray, 8);
}

/*
void CreateSyncButton() { 
   int x = SyncBtnX;
   int y = SyncBtnY;
   if(!ShowUIPanel) {
      x = ListX;
      y = ListY;
   }
   ObjectCreate(0, BUTTON_SYNC, OBJ_BUTTON, 0, 0, 0); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_YDISTANCE, y); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_XSIZE, 48); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_YSIZE, 22); 
   ObjectSetString(0, BUTTON_SYNC, OBJPROP_TEXT, "同步"); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_BGCOLOR, clrOrangeRed);
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_COLOR, clrWhite); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_FONTSIZE, 8); 
   ObjectSetInteger(0, BUTTON_SYNC, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
}
*/

void RefreshAlertList() {
   ObjectsDeleteAll(0, OBJ_LIST_PREFIX); // 只刪除警報文字項目
   // ObjectsDeleteAll(0, "NC_AL_"); // 原本這句會把獨立視窗也砍掉造成閃爍，現在不坎了，改為精確刪除
   ObjectDelete(0, "NC_AL_Title");
   ObjectDelete(0, "NC_AL_Page");
   ObjectDelete(0, "NC_AL_BtnUp");
   ObjectDelete(0, "NC_AL_BtnDn");

   if(!ShowAlertList && !ShowAlertWindow) return; // 都關閉則不繪製
   if(g_isMinimized && !ShowAlertWindow) return;  // 如果只依賴主面板且縮小，不繪製

   //-- 階段 1：收集符合條件的警報
   int validAlerts[];
   ArrayResize(validAlerts, 0);
   for(int i=1; i<=ALERT_MAX_ID; i++) {
      string k = ALERT_PREFIX + IntegerToString(i) + "_Active";
      if(!GlobalVariableCheck(k) || (int)GlobalVariableGet(k) != 1) continue;
      string sym = ReadAlertSymbol(i);
      if(sym == "") continue; // 防呆：檔案讀取中鎖定時不繪入有效列表，避免清單跳動
      if(!ShowAllSymbolsAlerts && sym != Symbol()) continue;

      bool isEma = (GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_EMA50") && (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA50") == 1);
      bool isBB  = GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_BB");
      if(isEma) {
         int targetTF = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_TF");
         if(!ShowAllSymbolsAlerts && targetTF != Period()) continue; 
      } else if(isBB) {
         int targetTF = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_IND_TF");
         if(!ShowAllSymbolsAlerts && targetTF != Period()) continue;
      }
      
      int size = ArraySize(validAlerts);
      ArrayResize(validAlerts, size+1);
      validAlerts[size] = i;
   }

   int totalAlerts = ArraySize(validAlerts);
   int totalPages = (totalAlerts == 0) ? 1 : (totalAlerts - 1) / MaxAlertsPerPage + 1;
   if(g_listPage >= totalPages) g_listPage = totalPages - 1;
   if(g_listPage < 0) g_listPage = 0;

   //-- 階段 2：決定繪製位置
   int baseY = 0, baseX = 0;
   if(ShowAlertWindow) {
      baseX = AlertWinX; baseY = AlertWinY;
      int winH = 40 + (totalAlerts > 0 ? (MathMin(totalAlerts - g_listPage * MaxAlertsPerPage, MaxAlertsPerPage) * 20) : 20);
      
      // 背景框：如果不存在才建立，存在的話只更新高度，這能徹底解決閃爍
      if(ObjectFind(0, "NC_AL_BG") < 0) CreatePanel("NC_AL_BG", baseX-10, baseY-10, 230, winH, C'30,30,40');
      else ObjectSetInteger(0, "NC_AL_BG", OBJPROP_YSIZE, winH);
      
      CreateLabel("NC_AL_Title", baseX, baseY, "📋 獨立警報清單", clrSkyBlue, 9);
      
      // 分頁控制鈕
      string pageStr = "Page " + IntegerToString(g_listPage+1) + "/" + IntegerToString(totalPages);
      CreateLabel("NC_AL_Page", baseX+140, baseY, pageStr, clrSilver, 8);
      CreateButton("NC_AL_BtnUp", baseX+85, baseY-2, 20, 16, "▲", clrWhite, C'60,60,60');
      CreateButton("NC_AL_BtnDn", baseX+110, baseY-2, 20, 16, "▼", clrWhite, C'60,60,60');
      
      baseY += 25; // 列表起始位移
   } else {
      ObjectDelete(0, "NC_AL_BG"); // 如果關閉了視窗模式，把背景砍掉
      baseX = ListX; baseY = ListY + 145; 
   }

   //-- 階段 3：繪製當前頁的警報項目
   int startIdx = ShowAlertWindow ? (g_listPage * MaxAlertsPerPage) : 0;
   int endIdx = ShowAlertWindow ? MathMin(startIdx + MaxAlertsPerPage, totalAlerts) : totalAlerts;
   int r = 0;
   
   for(int c = startIdx; c < endIdx; c++) {
      int i = validAlerts[c];
      string sym = ReadAlertSymbol(i);
      bool isEma = (GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_EMA_TYPE") && (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_TYPE") == 1) || 
                   (GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_EMA50") && (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA50") == 1);
      bool isBB  = GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_BB");
      string dynSuffix = "";
      if(isEma) { 
         int p_ema = GlobalVariableCheck(ALERT_PREFIX + IntegerToString(i) + "_EMA_P") ? (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_P") : 50;
         dynSuffix = "EMA" + IntegerToString(p_ema); 
      } 
      else if(isBB) {
         int bbMode = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_BB");
         dynSuffix = (bbMode == 1) ? " (BBH)" : " (BBL)";
      }
      
      double p = GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Price");
      int ab = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_Above");
      int symDigits = (int)SymbolInfoInteger(sym, SYMBOL_DIGITS);
      if(symDigits <= 0) symDigits = 5;

      string displayInfo = "";
      if(isEma) {
         int targetTF = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_EMA_TF");
         displayInfo = GetTfString((ENUM_TIMEFRAMES)targetTF) + "EMA";
      } else if(isBB) {
         int targetTF = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_IND_TF");
         int bbMode = (int)GlobalVariableGet(ALERT_PREFIX + IntegerToString(i) + "_BB");
         displayInfo = GetTfString((ENUM_TIMEFRAMES)targetTF) + (bbMode == 1 ? "BBH" : "BBL");
      } else {
         displayInfo = DoubleToString(p, symDigits);
      }

      string lblTxt = sym + " " + displayInfo;
      if(isEma || isBB) lblTxt += " @" + DoubleToString(p, symDigits);
      lblTxt += (ab==1?" ▲":" ▼");
      
      CreateLabel(OBJ_LIST_PREFIX+"L"+(string)i, baseX, baseY+r*20, lblTxt, (ab==1?clrLime:clrTomato), 8);
      CreateButton(OBJ_LIST_PREFIX+"Del_"+(string)i, baseX+180, baseY-2+r*20, 30, 16, "✕", clrWhite, C'150,0,0');
      r++;
   }

   ChartRedraw(0); // 立即執行最後的重繪
}

void SetStatus(string t) { ObjectSetString(0, OBJ_STATUS, OBJPROP_TEXT, t); }

void CreateLabel(string n, int x, int y, string t, color c, int s) { 
   ObjectCreate(0,n,OBJ_LABEL,0,0,0); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); 
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y); ObjectSetString(0,n,OBJPROP_TEXT,t); 
   ObjectSetInteger(0,n,OBJPROP_COLOR,c); ObjectSetInteger(0,n,OBJPROP_FONTSIZE,s); 
}

void CreateEdit(string n, int x, int y, int w, int h, string t) { 
   ObjectCreate(0,n,OBJ_EDIT,0,0,0); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); 
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y); ObjectSetInteger(0,n,OBJPROP_XSIZE,w); 
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h); ObjectSetString(0,n,OBJPROP_TEXT,t);
   ObjectSetInteger(0,n,OBJPROP_BGCOLOR,C'50,50,50'); ObjectSetInteger(0,n,OBJPROP_COLOR,clrWhite); 
}

void CreateButton(string n, int x, int y, int w, int h, string t, color tc, color bc) { 
   ObjectCreate(0,n,OBJ_BUTTON,0,0,0); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); 
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y); ObjectSetInteger(0,n,OBJPROP_XSIZE,w); 
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h); ObjectSetString(0,n,OBJPROP_TEXT,t); 
   ObjectSetInteger(0,n,OBJPROP_COLOR,tc); ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bc); 
   ObjectSetInteger(0,n,OBJPROP_FONTSIZE, 8); 
}

void CreatePanel(string n, int x, int y, int w, int h, color bc) { 
   ObjectCreate(0,n,OBJ_RECTANGLE_LABEL,0,0,0); ObjectSetInteger(0,n,OBJPROP_XDISTANCE,x); 
   ObjectSetInteger(0,n,OBJPROP_YDISTANCE,y); ObjectSetInteger(0,n,OBJPROP_XSIZE,w); 
   ObjectSetInteger(0,n,OBJPROP_YSIZE,h); ObjectSetInteger(0,n,OBJPROP_BGCOLOR,bc); 
   ObjectSetInteger(0,n,OBJPROP_BACK,true); 
}

void UpdateUIVisibility() {
   long tf = g_isMinimized ? OBJ_NO_PERIODS : OBJ_ALL_PERIODS;
   ObjectSetInteger(0, OBJ_INPUT_PRICE, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_INPUT_MSG, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_BTN_ADD, OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, "NC_BtnEMA", OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, "NC_BtnEMA2", OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, "NC_BtnBBH", OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, "NC_BtnBBL", OBJPROP_TIMEFRAMES, tf);
   ObjectSetInteger(0, OBJ_STATUS, OBJPROP_TIMEFRAMES, tf);
   
   if(g_isMinimized) {
      ObjectSetInteger(0, "NC_BG", OBJPROP_YSIZE, 25);
      ObjectSetString(0, "NC_BtnMin", OBJPROP_TEXT, "▼");
   } else {
      ObjectSetInteger(0, "NC_BG", OBJPROP_YSIZE, 145);
      ObjectSetString(0, "NC_BtnMin", OBJPROP_TEXT, "▲");
   }
   RefreshAlertList();
}

void OnTick() {}
