//+------------------------------------------------------------------+
//|                                                    TelegramNotifyEA.mq5 |
//|                        Copyright 2025, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2025, MetaQuotes Software Corp."
#property link      "https://www.mql5.com"
#property version   "1.00"

#include <Trade\PositionInfo.mqh>
#include <Trade\Trade.mqh>

// Helper: convert single byte to 2-digit hex string
string ByteToHex(uchar v)
{
    string hexChars = "0123456789ABCDEF";
    int hi = (int)(v / 16);
    int lo = (int)(v % 16);
    string s = StringSubstr(hexChars, hi, 1) + StringSubstr(hexChars, lo, 1);
    return s;
}

// Struct for position
struct PositionData
{
    long ticket;
    string symbol;
    ENUM_POSITION_TYPE type;
    double volume;
    double price;
    double sl;
    double tp;
};

// Struct for order
struct OrderData
{
    long ticket;
    string symbol;
    ENUM_ORDER_TYPE type;
    double volume;
    double price;
    double sl;
    double tp;
};

// Input parameters
input string botToken = "";          // Telegram Bot Token
input string chatIds = "";           // Telegram Chat IDs, separated by comma
input bool sendChartScreenshot = true; // Send chart screenshot when opening position
//input bool debugSendTest = false;    // If true, send a small test document on init for debugging

// Global variables
PositionData prevPositions[];
OrderData prevOrders[];
long chatIdsArray[];

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
    // Check if botToken and chatIds are provided
    if (botToken == "" || chatIds == "")
    {
        Print("Error: Bot Token and Chat IDs are required!");
        return INIT_PARAMETERS_INCORRECT;
    }

    // Parse chat IDs
    string parts[];
    int count = StringSplit(chatIds, ',', parts);
    ArrayResize(chatIdsArray, count);
    for (int i = 0; i < count; i++)
    {
        StringTrimLeft(parts[i]);
        StringTrimRight(parts[i]);
        chatIdsArray[i] = StringToInteger(parts[i]);
    }

    // Initialize prev data
    UpdatePrevPositions();
    UpdatePrevOrders();
    // Optional debug: send small test document to verify multipart upload
    //if (debugSendTest)
    //{
        //SendTestDocument();
    //}

    Print("Telegram Notify EA initialized.");
    return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
    // Nothing to do
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
    // Check for changes
    CheckPositionChanges();
    CheckOrderChanges();

    // Update prev data
    UpdatePrevPositions();
    UpdatePrevOrders();
}

//+------------------------------------------------------------------+
//| Check for position changes                                       |
//+------------------------------------------------------------------+
void CheckPositionChanges()
{
    CPositionInfo posInfo;
    // Check for closed positions
    for (int i = 0; i < ArraySize(prevPositions); i++)
    {
        bool found = false;
        for (int j = 0; j < PositionsTotal(); j++)
        {
            if (posInfo.SelectByIndex(j) && posInfo.Ticket() == (ulong)prevPositions[i].ticket)
            {
                found = true;
                // Check for modifications
                if (posInfo.StopLoss() != prevPositions[i].sl || posInfo.TakeProfit() != prevPositions[i].tp)
                {
                    string symbol = prevPositions[i].symbol;
                    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                    string message = "Position Modified:\nTicket: <b>" + IntegerToString(prevPositions[i].ticket) + "</b>\nSymbol: <b>" + symbol + "</b>\nSL: <b>" + DoubleToString(posInfo.StopLoss(), digits) + "</b>\nTP: <b>" + DoubleToString(posInfo.TakeProfit(), digits) + "</b>";
                    SendTelegramMessage(message);
                }
                break;
            }
        }
        if (!found)
        {
            string symbol = prevPositions[i].symbol;
            double pnl = 0;
            // Calculate P&L from history
            if (HistorySelect(0, TimeCurrent()))
            {
                for (int k = HistoryDealsTotal() - 1; k >= 0; k--)
                {
                    ulong dealTicket = HistoryDealGetTicket(k);
                    if (HistoryDealGetString(dealTicket, DEAL_SYMBOL) == symbol && HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID) == prevPositions[i].ticket)
                    {
                        pnl += HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
                    }
                }
            }
            string pnlStr = (pnl >= 0) ? "✅ +" : "❌ ";
            pnlStr += "<b>" + DoubleToString(pnl, 2) + "</b>";
            string message = "Position Closed:\nTicket: <b>" + IntegerToString(prevPositions[i].ticket) + "</b>\nSymbol: <b>" + symbol + "</b>\nP&L: " + pnlStr;
            SendTelegramMessage(message);
        }
    }

    // Check for new positions
    for (int j = 0; j < PositionsTotal(); j++)
    {
        if (posInfo.SelectByIndex(j))
        {
            bool found = false;
            for (int i = 0; i < ArraySize(prevPositions); i++)
            {
                if (posInfo.Ticket() == (ulong)prevPositions[i].ticket)
                {
                    found = true;
                    break;
                }
            }
            if (!found)
            {
                string symbol = posInfo.Symbol();
                int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                string type = (posInfo.PositionType() == POSITION_TYPE_BUY) ? "📈 BUY" : "📉 SELL";
                string message = "Position Opened:\n" + type + "\nTicket: <b>" + IntegerToString(posInfo.Ticket()) + "</b>\nSymbol: <b>" + symbol + "</b>\nVolume: <b>" + DoubleToString(posInfo.Volume(), 2) + "</b>\nPrice: <b>" + DoubleToString(posInfo.PriceOpen(), digits) + "</b>\nSL: <b>" + DoubleToString(posInfo.StopLoss(), digits) + "</b>\nTP: <b>" + DoubleToString(posInfo.TakeProfit(), digits) + "</b>";
                if (sendChartScreenshot)
                {
                    SendTelegramPhoto(posInfo.Ticket(), message);
                }
                else
                {
                    SendTelegramMessage(message);
                }
            }
        }
    }
}

//+------------------------------------------------------------------+
//| Check for order changes                                          |
//+------------------------------------------------------------------+
void CheckOrderChanges()
{
    // Check for deleted orders
    for (int i = 0; i < ArraySize(prevOrders); i++)
    {
        bool found = false;
        for (int j = 0; j < OrdersTotal(); j++)
        {
            ulong ticket = OrderGetTicket(j);
            if (ticket == (ulong)prevOrders[i].ticket)
            {
                found = true;
                // Check for modifications
                double sl = OrderGetDouble(ORDER_SL);
                double tp = OrderGetDouble(ORDER_TP);
                if (sl != prevOrders[i].sl || tp != prevOrders[i].tp)
                {
                    string symbol = prevOrders[i].symbol;
                    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                    string message = "Order Modified:\nTicket: <b>" + IntegerToString(prevOrders[i].ticket) + "</b>\nSymbol: <b>" + symbol + "</b>\nSL: <b>" + DoubleToString(sl, digits) + "</b>\nTP: <b>" + DoubleToString(tp, digits) + "</b>";
                    SendTelegramMessage(message);
                }
                break;
            }
        }
        if (!found)
        {
            // Order deleted
            string message = "Order Deleted:\nTicket: <b>" + IntegerToString(prevOrders[i].ticket) + "</b>\nSymbol: <b>" + prevOrders[i].symbol + "</b>";
            SendTelegramMessage(message);
        }
    }

    // Check for new orders
    for (int j = 0; j < OrdersTotal(); j++)
    {
        ulong ticket = OrderGetTicket(j);
        bool found = false;
        for (int i = 0; i < ArraySize(prevOrders); i++)
        {
            if (ticket == (ulong)prevOrders[i].ticket)
            {
                found = true;
                break;
            }
        }
        if (!found)
        {
            string symbol = OrderGetString(ORDER_SYMBOL);
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
            string type = "";
            ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            if (orderType == ORDER_TYPE_BUY_LIMIT) type = "🟢⬆️ BUY LIMIT";
            else if (orderType == ORDER_TYPE_SELL_LIMIT) type = "🔴⬇️ SELL LIMIT";
            else if (orderType == ORDER_TYPE_BUY_STOP) type = "🟢⬆️ BUY STOP";
            else if (orderType == ORDER_TYPE_SELL_STOP) type = "🔴⬇️ SELL STOP";
            else type = "UNKNOWN";

            string message = "Order Placed:\n" + type + "\nTicket: <b>" + IntegerToString(ticket) + "</b>\nSymbol: <b>" + symbol + "</b>\nVolume: <b>" + DoubleToString(OrderGetDouble(ORDER_VOLUME_CURRENT), 2) + "</b>\nPrice: <b>" + DoubleToString(OrderGetDouble(ORDER_PRICE_OPEN), digits) + "</b>\nSL: <b>" + DoubleToString(OrderGetDouble(ORDER_SL), digits) + "</b>\nTP: <b>" + DoubleToString(OrderGetDouble(ORDER_TP), digits) + "</b>";
            SendTelegramMessage(message);
        }
    }
}

//+------------------------------------------------------------------+
//| Update previous positions                                        |
//+------------------------------------------------------------------+
void UpdatePrevPositions()
{
    CPositionInfo posInfo;
    ArrayResize(prevPositions, PositionsTotal());
    for (int i = 0; i < PositionsTotal(); i++)
    {
        if (posInfo.SelectByIndex(i))
        {
            prevPositions[i].ticket = (long)posInfo.Ticket();
            prevPositions[i].symbol = posInfo.Symbol();
            prevPositions[i].type = posInfo.PositionType();
            prevPositions[i].volume = posInfo.Volume();
            prevPositions[i].price = posInfo.PriceOpen();
            prevPositions[i].sl = posInfo.StopLoss();
            prevPositions[i].tp = posInfo.TakeProfit();
        }
    }
}

//+------------------------------------------------------------------+
//| Update previous orders                                           |
//+------------------------------------------------------------------+
void UpdatePrevOrders()
{
    ArrayResize(prevOrders, OrdersTotal());
    for (int i = 0; i < OrdersTotal(); i++)
    {
        ulong ticket = OrderGetTicket(i);
        if (ticket > 0)
        {
            prevOrders[i].ticket = (long)ticket;
            prevOrders[i].symbol = OrderGetString(ORDER_SYMBOL);
            prevOrders[i].type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            prevOrders[i].volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
            prevOrders[i].price = OrderGetDouble(ORDER_PRICE_OPEN);
            prevOrders[i].sl = OrderGetDouble(ORDER_SL);
            prevOrders[i].tp = OrderGetDouble(ORDER_TP);
        }
    }
}

//+------------------------------------------------------------------+
//| Send message to Telegram                                         |
//+------------------------------------------------------------------+
void SendTelegramMessage(string text)
{
    for (int i = 0; i < ArraySize(chatIdsArray); i++)
    {
        string url = "https://api.telegram.org/bot" + botToken + "/sendMessage";
        string headers = "Content-Type: application/json";
        string postData = "{\"chat_id\":" + IntegerToString(chatIdsArray[i]) + ",\"text\":\"" + text + "\",\"parse_mode\":\"HTML\"}";
        char postArray[];
        StringToCharArray(postData, postArray, 0, WHOLE_ARRAY, 65001);
        char result[];
        string resultHeaders;
        int timeout = 5000;

        int res = WebRequest("POST", url, headers, timeout, postArray, result, resultHeaders);

        if (res == -1)
        {
            Print("Failed to send Telegram message to chat " + IntegerToString(chatIdsArray[i]) + ". Error: " + IntegerToString(GetLastError()));
        }
        else
        {
            Print("Telegram message sent to chat " + IntegerToString(chatIdsArray[i]));
        }
    }
}

//+------------------------------------------------------------------+
//| Send photo to Telegram                                           |
//+------------------------------------------------------------------+
void SendTelegramPhoto(long ticket, string caption)
{
    if (!sendChartScreenshot) return;

    string filename = "screenshot_" + IntegerToString(ticket) + ".png";
    string filepath = filename; // Files are saved in MQL5/Files

    // Take screenshot
    if (!ChartScreenShot(0, filepath, 800, 600, ALIGN_RIGHT))
    {
        Print("Failed to take screenshot for ticket " + IntegerToString(ticket));
        return;
    }

    for (int i = 0; i < ArraySize(chatIdsArray); i++)
    {
        // Always send as document (more reliable for arbitrary binary)
        string url = "https://api.telegram.org/bot" + botToken + "/sendDocument";
        string boundary = "----WebKitFormBoundary7MA4YWxkTrZu0gW";
        string headers = "Content-Type: multipart/form-data; boundary=" + boundary;

        // Read file (binary) into uchar then convert to char for WebRequest
        int filehandle = FileOpen(filepath, FILE_READ | FILE_BIN);
        if (filehandle == INVALID_HANDLE)
        {
            Print("Failed to open screenshot file: " + filepath + ", error: " + IntegerToString(GetLastError()));
            continue;
        }
        int filesize = (int)FileSize(filehandle);
        Print("Screenshot file size: " + IntegerToString(filesize));
        uchar fileU[];
        ArrayResize(fileU, filesize);
        FileReadArray(filehandle, fileU, 0, filesize);
        FileClose(filehandle);

        char filedata[];
        ArrayResize(filedata, filesize);
        for (int b = 0; b < filesize; b++)
            filedata[b] = (char)fileU[b];

        // Build multipart body as char array with 'document' field plus caption and parse_mode
        string header1 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + IntegerToString(chatIdsArray[i]) + "\r\n";
        // Trim caption to Telegram limit (1024 chars)
        string cap = caption;
        if (StringLen(cap) > 1024) cap = StringSubstr(cap, 0, 1024);
        string headerCaption = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"caption\"\r\n\r\n" + cap + "\r\n";
        string headerParse = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"parse_mode\"\r\n\r\nHTML\r\n";
        string header2 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"document\"; filename=\"" + filename + "\"\r\nContent-Type: image/png\r\n\r\n";
        string footer = "\r\n--" + boundary + "--\r\n";

        char header1Array[];
        char headerCaptionArray[];
        char headerParseArray[];
        char header2Array[];
        char footerArray[];
        StringToCharArray(header1, header1Array, 0, WHOLE_ARRAY, CP_UTF8);
        StringToCharArray(headerCaption, headerCaptionArray, 0, WHOLE_ARRAY, CP_UTF8);
        StringToCharArray(headerParse, headerParseArray, 0, WHOLE_ARRAY, CP_UTF8);
        StringToCharArray(header2, header2Array, 0, WHOLE_ARRAY, CP_UTF8);
        StringToCharArray(footer, footerArray, 0, WHOLE_ARRAY, CP_UTF8);

        int h1len = ArraySize(header1Array); if (h1len>0 && header1Array[h1len-1]==0) h1len--;
        int hcaplen = ArraySize(headerCaptionArray); if (hcaplen>0 && headerCaptionArray[hcaplen-1]==0) hcaplen--;
        int hparlen = ArraySize(headerParseArray); if (hparlen>0 && headerParseArray[hparlen-1]==0) hparlen--;
        int h2len = ArraySize(header2Array); if (h2len>0 && header2Array[h2len-1]==0) h2len--;
        int flen = ArraySize(filedata);
        int fend = ArraySize(footerArray); if (fend>0 && footerArray[fend-1]==0) fend--;

        int totalSize = h1len + hcaplen + hparlen + h2len + flen + fend;
        char postData[];
        ArrayResize(postData, totalSize);

        int offset = 0;
        ArrayCopy(postData, header1Array, offset, 0, h1len); offset += h1len;
        ArrayCopy(postData, headerCaptionArray, offset, 0, hcaplen); offset += hcaplen;
        ArrayCopy(postData, headerParseArray, offset, 0, hparlen); offset += hparlen;
        ArrayCopy(postData, header2Array, offset, 0, h2len); offset += h2len;
        ArrayCopy(postData, filedata, offset, 0, flen); offset += flen;
        ArrayCopy(postData, footerArray, offset, 0, fend);

        Print("Post data size: " + IntegerToString(ArraySize(postData)));

        char result[];
        string resultHeaders;
        int timeout = 20000;

        int res = WebRequest("POST", url, headers, timeout, postData, result, resultHeaders);
        Print("sendDocument WebRequest res: " + IntegerToString(res));
        Print("Result array size: " + IntegerToString(ArraySize(result)));
        Print("Result headers: " + resultHeaders);
        string response = CharArrayToString(result);
        Print("sendDocument API response: " + response);

        if (res == -1 || StringFind(response, "\"ok\":true") == -1)
        {
            Print("Telegram document send failed to chat " + IntegerToString(chatIdsArray[i]) + ". Response: " + response + ", Error: " + IntegerToString(GetLastError()));
        }
        else
        {
            Print("Telegram document sent successfully to chat " + IntegerToString(chatIdsArray[i]));
        }

        // Delete file after sending
        if (FileDelete(filepath))
            Print("Screenshot file deleted: " + filepath);
        else
            Print("Failed to delete screenshot file: " + filepath + ", error: " + IntegerToString(GetLastError()));
    }
}
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Send a small test document and dump multipart headers (debug)    |
//+------------------------------------------------------------------+
void SendTestDocument()
{
    string filename = "test_doc.txt";
    string filepath = filename;

    // create test file
    int fh = FileOpen(filepath, FILE_WRITE | FILE_TXT | FILE_ANSI);
    if (fh == INVALID_HANDLE)
    {
        Print("Failed to create test file: " + filepath + ", error: " + IntegerToString(GetLastError()));
        return;
    }
    FileWriteString(fh, "Hello Telegram test\n");
    FileClose(fh);

    // Build a minimal multipart body and send as document
    string boundary = "----WebKitFormBoundaryTest12345";
    string url = "https://api.telegram.org/bot" + botToken + "/sendDocument";
    string headers = "Content-Type: multipart/form-data; boundary=" + boundary;

    // Read file into uchar
    int filehandle = FileOpen(filepath, FILE_READ | FILE_BIN);
    if (filehandle == INVALID_HANDLE)
    {
        Print("Failed to open test file for reading: " + filepath + ", error: " + IntegerToString(GetLastError()));
        return;
    }
    int filesize = (int)FileSize(filehandle);
    uchar fileU[];
    ArrayResize(fileU, filesize);
    FileReadArray(filehandle, fileU, 0, filesize);
    FileClose(filehandle);

    // build headers
    string h1 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"chat_id\"\r\n\r\n" + IntegerToString(chatIdsArray[0]) + "\r\n";
    string h2 = "--" + boundary + "\r\nContent-Disposition: form-data; name=\"document\"; filename=\"" + filename + "\"\r\nContent-Type: text/plain\r\n\r\n";
    string footer = "\r\n--" + boundary + "--\r\n";

    char h1Arr[]; StringToCharArray(h1, h1Arr, 0, WHOLE_ARRAY, CP_UTF8);
    char h2Arr[]; StringToCharArray(h2, h2Arr, 0, WHOLE_ARRAY, CP_UTF8);
    char footArr[]; StringToCharArray(footer, footArr, 0, WHOLE_ARRAY, CP_UTF8);

    int h1len = ArraySize(h1Arr); if (h1len>0 && h1Arr[h1len-1]==0) h1len--;
    int h2len = ArraySize(h2Arr); if (h2len>0 && h2Arr[h2len-1]==0) h2len--;
    int fend = ArraySize(footArr); if (fend>0 && footArr[fend-1]==0) fend--;

    int total = h1len + h2len + filesize + fend;
    char post[]; ArrayResize(post, total);

    int off = 0;
    ArrayCopy(post, h1Arr, off, 0, h1len); off += h1len;
    ArrayCopy(post, h2Arr, off, 0, h2len); off += h2len;
    // copy binary
    for (int i = 0; i < filesize; i++) post[off + i] = (char)fileU[i];
    off += filesize;
    ArrayCopy(post, footArr, off, 0, fend);

    // log small hex dump of the beginning of post
    int dumpLen = MathMin(128, ArraySize(post));
    string hex="";
    for (int k = 0; k < dumpLen; k++)
    {
        uchar v = (uchar)post[k];
        string hh = ByteToHex(v);
        hex += hh + " ";
    }
    Print("[DEBUG] multipart start (hex, first " + IntegerToString(dumpLen) + " bytes): " + hex);

    char result[]; string resultHeaders; int timeout = 10000;
    int res = WebRequest("POST", url, headers, timeout, post, result, resultHeaders);
    string resp = CharArrayToString(result);
    Print("[DEBUG] sendTestDocument WebRequest res: " + IntegerToString(res));
    Print("[DEBUG] sendTestDocument API response: " + resp);

    // cleanup
    FileDelete(filepath);
}

