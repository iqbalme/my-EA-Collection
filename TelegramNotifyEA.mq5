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
                int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
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
                int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
                string type = (posInfo.PositionType() == POSITION_TYPE_BUY) ? "🟢⬆️ BUY" : "🔴⬇️ SELL";
                string message = "Position Opened:\n" + type + "\nTicket: <b>" + IntegerToString(posInfo.Ticket()) + "</b>\nSymbol: <b>" + symbol + "</b>\nVolume: <b>" + DoubleToString(posInfo.Volume(), 2) + "</b>\nPrice: <b>" + DoubleToString(posInfo.PriceOpen(), digits) + "</b>\nSL: <b>" + DoubleToString(posInfo.StopLoss(), digits) + "</b>\nTP: <b>" + DoubleToString(posInfo.TakeProfit(), digits) + "</b>";
                SendTelegramMessage(message);
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
                int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
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
            int digits = SymbolInfoInteger(symbol, SYMBOL_DIGITS);
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
        StringToCharArray(postData, postArray, 0, WHOLE_ARRAY, CP_UTF8);
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