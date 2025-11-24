//+------------------------------------------------------------------+
//|                                                    TelegramSignalEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

// Input parameters
input string botToken = "";          // Telegram Bot Token
input string allowedChatIds = "";    // Allowed Chat IDs, separated by comma
input bool useFixedLot = true;       // Use fixed lot size
input double fixedLot = 0.01;        // Fixed lot size
input double riskPercent = 1.0;      // Risk percentage for dynamic lot
input int pollingInterval = 10;      // Polling interval in seconds

// Global variables
string lastUpdateIdFile = "last_id.txt";
long lastUpdateId = 0;
datetime lastPollingTime = 0;
long allowedChats[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Check if botToken is provided
    if (botToken == "")
    {
        Print("Error: Bot Token is required!");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Parse allowed chat IDs
    if (allowedChatIds != "")
    {
        string parts[];
        int count = StringSplit(allowedChatIds, ',', parts);
        ArrayResize(allowedChats, count);
        for (int i = 0; i < count; i++)
        {
            StringTrimLeft(parts[i]);
            StringTrimRight(parts[i]);
            allowedChats[i] = StringToInteger(parts[i]);
        }
    }
    else
    {
        Print("Error: Allowed Chat IDs are required!");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Load last update ID from file
    lastUpdateId = LoadLastUpdateId();

    // Set up WebRequest (ensure Telegram API is allowed in Terminal Options)
    // Terminal -> Options -> Expert Advisors -> Allow WebRequest for listed URLs
    // Add: https://api.telegram.org

    Print("Telegram Signal EA initialized. Polling for signals...");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Save last update ID on deinit
    SaveLastUpdateId(lastUpdateId);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Polling every pollingInterval seconds
    //if (TimeCurrent() - lastPollingTime < pollingInterval)
    //    return;

    lastPollingTime = TimeCurrent();

    // Fetch updates from Telegram
    string response = FetchTelegramUpdates();
    if (response == "")
    {
        Print("Failed to fetch updates from Telegram.");
        return;
    }

    // Parse updates
    ParseUpdates(response);
}

//+------------------------------------------------------------------+
//| Fetch updates from Telegram API                                  |
//+------------------------------------------------------------------+
string FetchTelegramUpdates()
{
    string url = "https://api.telegram.org/bot" + botToken + "/getUpdates";
    if (lastUpdateId > 0)
        url += "?offset=" + IntegerToString(lastUpdateId + 1);

    string headers = "Content-Type: application/json";
    char postData[];
    char result[];
    string resultHeaders;
    int timeout = 5000; // 5 seconds

    int res = WebRequest("GET", url, headers, timeout, postData, result, resultHeaders);

    if (res == -1)
    {
        Print("WebRequest failed. Error: " + IntegerToString(GetLastError()));
        return "";
    }

    string response = CharArrayToString(result);
    return response;
}

//+------------------------------------------------------------------+
//| Parse Telegram updates                                           |
//+------------------------------------------------------------------+
void ParseUpdates(string response)
{
    // Simple JSON parsing (MQL5 doesn't have built-in JSON, so basic string parsing)
    // Look for "update_id" and "text" in messages

    string search = "\"update_id\":";
    int pos = StringFind(response, search);
    while (pos != -1)
    {
        // Extract update_id
        int start = pos + StringLen(search);
        int end = StringFind(response, ",", start);
        if (end == -1) end = StringFind(response, "}", start);
        string updateIdStr = StringSubstr(response, start, end - start);
        long updateId = StringToInteger(updateIdStr);

        // Check if already processed
        if (updateId <= lastUpdateId)
        {
            pos = StringFind(response, search, pos + 1);
            continue;
        }

        // Extract chat_id
        string chatSearch = "\"chat\":{\"id\":";
        int chatPos = StringFind(response, chatSearch, pos);
        if (chatPos == -1) break;
        int chatStart = chatPos + StringLen(chatSearch);
        int chatEnd = StringFind(response, ",", chatStart);
        string chatIdStr = StringSubstr(response, chatStart, chatEnd - chatStart);
        long chatId = StringToInteger(chatIdStr);

        // Check allowed chat
        if (!IsChatAllowed(chatId))
        {
            pos = StringFind(response, search, pos + 1);
            continue;
        }

        // Extract text
        string textSearch = "\"text\":\"";
        int textPos = StringFind(response, textSearch, pos);
        if (textPos == -1) break;
        int textStart = textPos + StringLen(textSearch);
        int textEnd = StringFind(response, "\"", textStart);
        string text = StringSubstr(response, textStart, textEnd - textStart);

        // Sanitize text
        text = SanitizeText(text);

        Print("Received message from chat " + IntegerToString(chatId) + ": " + text);

        // Parse signal
        if (ParseSignal(text))
        {
            lastUpdateId = updateId;
            SaveLastUpdateId(lastUpdateId);
        }

        pos = StringFind(response, search, pos + 1);
    }
}

//+------------------------------------------------------------------+
//| Sanitize text for parsing                                        |
//+------------------------------------------------------------------+
string SanitizeText(string text)
{
    // Remove extra spaces, newlines
    StringReplace(text, "\n", " ");
    StringReplace(text, "\r", " ");
    while (StringFind(text, "  ") != -1)
        StringReplace(text, "  ", " ");
    StringTrimLeft(text);
    StringTrimRight(text);
    return text;
}

//+------------------------------------------------------------------+
//| Parse signal from text                                           |
//+------------------------------------------------------------------+
bool ParseSignal(string text)
{
    Print("Parsing signal: " + text);

    // Use regex-like parsing (MQL5 doesn't have regex, so manual parsing)
    // Expected format: Pair BUY/SELL Entry - SL TP1 TP2

    string pair = "";
    string direction = "";
    double entry = 0.0;
    double sl = 0.0;
    double tp1 = 0.0;
    double tp2 = 0.0;

    // Split by spaces
    string parts[];
    int count = StringSplit(text, ' ', parts);

    Print("Split into " + IntegerToString(count) + " parts");
    for (int i = 0; i < count; i++)
    {
        Print("Part " + IntegerToString(i) + ": '" + parts[i] + "'");
    }
    if (count < 6) 
    {
        Print("Not enough parts, skipping");
        return false;
    }

    // Assume format: RISKLEVEL Pair DIRECTION NOW AT Entry - SL TP1 TP2
    // Or simpler: Pair DIRECTION Entry SL TP1 TP2

    // Find BUY or SELL
    int dirIndex = -1;
    for (int i = 0; i < count; i++)
    {
        string temp = parts[i];
        StringToUpper(temp);
        string current = temp;
        Print("Checking part " + IntegerToString(i) + ": '" + parts[i] + "' -> '" + current + "'");
        if (current == "BUY" || current == "SELL")
        {
            dirIndex = i;
            direction = current;
            Print("Found direction: " + direction + " at index " + IntegerToString(i));
            break;
        }
    }
    if (dirIndex == -1) 
    {
        Print("No BUY/SELL found, skipping");
        return false;
    }

    Print("Direction: " + direction + ", dirIndex: " + IntegerToString(dirIndex));

    // Pair after direction
    if (dirIndex + 1 < count) pair = parts[dirIndex + 1];

    Print("Pair: " + pair);

    // Entry is market
    entry = 0.0; // Will use current price
    Print("Entry: market");

    // Find SL and TP
    for (int i = dirIndex + 2; i < count; i++)
    {
        string temp = parts[i];
        StringToUpper(temp);
        string current = temp;
        if (current == "SL" && i + 1 < count)
        {
            sl = StringToDouble(parts[i + 1]);
            Print("SL: " + DoubleToString(sl));
        }
        else if (current == "TP" && i + 1 < count)
        {
            tp1 = StringToDouble(parts[i + 1]);
            Print("TP: " + DoubleToString(tp1));
        }
    }

    if (sl == 0.0 || tp1 == 0.0)
    {
        Print("SL or TP not found, skipping");
        return false;
    }

    // Validate pair
    string tempPair = pair;
    StringToUpper(tempPair);
    string tempSymbol = Symbol();
    StringToUpper(tempSymbol);
    if (tempPair != tempSymbol)
    {
        Print("Signal pair " + pair + " does not match chart symbol " + Symbol());
        return false;
    }

    Print("Pair validated, executing order");

    // Execute order
    ExecuteOrder(direction, entry, sl, tp1, tp2);

    return true;
}

//+------------------------------------------------------------------+
//| Execute order                                                    |
//+------------------------------------------------------------------+
void ExecuteOrder(string direction, double entry, double sl, double tp1, double tp2)
{
    // Check if trading is allowed
    if (!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
    {
        Print("Trading not allowed in terminal");
        return;
    }
    if (!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
    {
        Print("Trading not allowed for account");
        return;
    }
    if (SymbolInfoInteger(Symbol(), SYMBOL_TRADE_MODE) == SYMBOL_TRADE_MODE_DISABLED)
    {
        Print("Trading disabled for symbol " + Symbol());
        return;
    }

    // Calculate lot size
    double lot = useFixedLot ? fixedLot : CalculateLotSize(sl);

    // Determine order type
    ENUM_ORDER_TYPE orderType = (direction == "BUY") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;

    // For market order, entry is current price
    double price = (direction == "BUY") ? SymbolInfoDouble(Symbol(), SYMBOL_ASK) : SymbolInfoDouble(Symbol(), SYMBOL_BID);

    // Validate SL/TP
    double point = SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    int digits = (int)SymbolInfoInteger(Symbol(), SYMBOL_DIGITS);
    double minStop = SymbolInfoInteger(Symbol(), SYMBOL_TRADE_STOPS_LEVEL) * point;
    if (direction == "BUY")
    {
        if (sl >= price - minStop || tp1 <= price + minStop)
        {
            Print("Invalid SL/TP for BUY: SL=" + DoubleToString(sl) + " TP=" + DoubleToString(tp1) + " Price=" + DoubleToString(price) + " MinStop=" + DoubleToString(minStop));
            return;
        }
    }
    else
    {
        if (sl <= price + minStop || tp1 >= price - minStop)
        {
            Print("Invalid SL/TP for SELL: SL=" + DoubleToString(sl) + " TP=" + DoubleToString(tp1) + " Price=" + DoubleToString(price) + " MinStop=" + DoubleToString(minStop));
            return;
        }
    }

    // Place order
    MqlTradeRequest request = {};
    MqlTradeResult result = {};

    request.action = TRADE_ACTION_DEAL;
    request.symbol = Symbol();
    request.volume = lot;
    request.type = orderType;
    request.price = price;
    request.sl = sl;
    request.tp = tp1; // Use TP1, TP2 can be handled separately if needed
    request.deviation = 10;
    request.magic = 123456;

    if (OrderSend(request, result))
    {
        Print("Order placed: " + direction + " " + Symbol() + " Lot: " + DoubleToString(lot) + " SL: " + DoubleToString(sl) + " TP: " + DoubleToString(tp1));
    }
    else
    {
        Print("Order failed: " + IntegerToString(GetLastError()) + " Retcode: " + IntegerToString(result.retcode));
    }
}

//+------------------------------------------------------------------+
//| Calculate lot size based on risk                                 |
//+------------------------------------------------------------------+
double CalculateLotSize(double sl)
{
    double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
    double riskAmount = accountBalance * riskPercent / 100.0;
    double price = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
    double slPoints = MathAbs(price - sl) / SymbolInfoDouble(Symbol(), SYMBOL_POINT);
    double tickValue = SymbolInfoDouble(Symbol(), SYMBOL_TRADE_TICK_VALUE);
    double lot = riskAmount / (slPoints * tickValue);
    lot = MathMin(lot, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MAX));
    lot = MathMax(lot, SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN));
    return NormalizeDouble(lot, 2);
}

//+------------------------------------------------------------------+
//| Save last update ID to file                                      |
//+------------------------------------------------------------------+
void SaveLastUpdateId(long id)
{
    int handle = FileOpen(lastUpdateIdFile, FILE_WRITE | FILE_TXT);
    if (handle != INVALID_HANDLE)
    {
        FileWriteString(handle, IntegerToString(id));
        FileClose(handle);
    }
    else
    {
        Print("Failed to save last update ID");
    }
}

//+------------------------------------------------------------------+
//| Load last update ID from file                                    |
//+------------------------------------------------------------------+
long LoadLastUpdateId()
{
    int handle = FileOpen(lastUpdateIdFile, FILE_READ | FILE_TXT);
    if (handle != INVALID_HANDLE)
    {
        string idStr = FileReadString(handle);
        FileClose(handle);
        return StringToInteger(idStr);
    }
    return 0;
}

//+------------------------------------------------------------------+
//| Check if string is numeric                                       |
//+------------------------------------------------------------------+
bool IsNumeric(string str)
{
    for (int i = 0; i < StringLen(str); i++)
    {
        ushort ch = StringGetCharacter(str, i);
        if (!((ch >= '0' && ch <= '9') || ch == '.'))
            return false;
    }
    return true;
}

//+------------------------------------------------------------------+
//| Check if chat ID is allowed                                      |
//+------------------------------------------------------------------+
bool IsChatAllowed(long chatId)
{
    for (int i = 0; i < ArraySize(allowedChats); i++)
    {
        if (allowedChats[i] == chatId)
            return true;
    }
    return false;
}
//+------------------------------------------------------------------+