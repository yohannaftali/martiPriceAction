//+---------------------------------------------------------------------------+
//|                                                    Martingle Price Action |
//|                                             Copyright 2024, Yohan Naftali |
//+---------------------------------------------------------------------------+
#property copyright "Copyright 2024, Yohan Naftali"
#property link      "https://github.com/yohannaftali"
#property version   "240.320"

// CTrade
#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>
#include <Trade\OrderInfo.mqh>
#include <Trade\DealInfo.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\AccountInfo.mqh>

CTrade trade;
CDealInfo deal;
COrderInfo order;
CPositionInfo position;
CAccountInfo account;

// Input
input group "Risk Management";
input double baseVolume = 0.01;      // Base Volume Size (Lot)
input double multiplierVolume = 1.6; // Size Multiplier
input int maximumStep = 15;          // Maximum Step

input group "Take Profit";
input double targetProfit = 90;      // Target Profit USD/lot

input group "Deviation Grid Step";
input double deviationStep = 0.04;   // Minimum Price Deviation Step (%)
input double multiplierStep = 1.2;   // Step Multipiler

input group "New Order Condition";
input ENUM_TIMEFRAMES timeframe = PERIOD_M5; // Timeframe Period
input int greenPeriod = 1;                   // Green Period
input int redPeriod = 3;                     // Red Period

// Variables
int currentStep = 0;
double minimumAskPrice = 0;
double nextOpenVolume = 0;
double nextSumVolume = 0;
double takeProfitPrice = 0;
int historyLast = 0;
int positionLast = 0;
int totalPeriod = redPeriod + greenPeriod;

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
int OnInit() {
  Print("# ----------------------------------");
  datetime current = TimeCurrent();
  datetime server = TimeTradeServer();
  datetime gmt = TimeGMT();
  datetime local = TimeLocal();

  Print("# Time Info");
  Print("- Current Time: " + TimeToString(current));
  Print("- Server Time: " + TimeToString(server));
  Print("- GMT Time: " + TimeToString(gmt));
  Print("- Local Time: " + TimeToString(local));

  Print("# Risk Management Info");
  Print("- Base Order Size: " + DoubleToString(baseVolume, 2) + " lot");
  Print("- Order Size Multiplier: " + DoubleToString(multiplierVolume, 2));
  Print("- Maximum Step: " + IntegerToString(maximumStep));
  Print("- Maximum Volume:" + DoubleToString(maximumVolume(), 2) + " lot");

  calculatePosition();
  return (INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTick() {
  if(currentStep == 0) {
    if(!isNewBar()) return;
    if(!priceActionTrigger()) return;
    // Open first order
    openTrade();
    return;
  }

// Exit if current step over than safety order count
  if(currentStep >= maximumStep) return;

  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
  if(ask > minimumAskPrice) return;
  openTrade();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void openTrade() {
  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
  string msg = "Buy step #" + IntegerToString(currentStep+1);
  double tp = NormalizeDouble(ask + (nextSumVolume*targetProfit), Digits());
  bool buy = trade.Buy(nextOpenVolume, Symbol(), 0.0, 0.0, tp, msg);
  if(!buy) {
    Print(trade.ResultComment());
  }

  calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void OnTrade() {
  int pos = PositionsTotal();
  if(positionLast == pos) return;
  positionLast = pos;
  if(pos > 0) return;
  Print("* Take Profit Event");
  Print("# Recalculate Position");
  calculatePosition();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void calculatePosition() {
  double sumVolume = 0;
  double sumProfit = 0;
  double sumVolumePrice = 0;

  double balance = account.Balance();
  double equity = account.Equity();
  double margin = account.Margin();
  double freeMargin = account.FreeMargin();
  Print("# Account Info");
  Print("- Balance: " + DoubleToString(balance, 2));
  Print("- Equity: " + DoubleToString(equity, 2));
  Print("- Margin: " + DoubleToString(margin, 2));
  Print("- Free Margin: " + DoubleToString(freeMargin, 2));

  Print("# Position Info");
  Print("- Total Position: " + IntegerToString(PositionsTotal()));

// Reset Current Step
  currentStep = 0;
  for(int i = 0; i < PositionsTotal(); i++) {
    bool isSelected = position.SelectByIndex(i);
    if(!isSelected) continue;
    ulong ticket = position.Ticket();
    double currentStopLoss = position.StopLoss();
    double currentTakeProfit = position.TakeProfit();
    double volume = position.Volume();
    sumVolume += volume;
    double price = position.PriceOpen();
    double volumePrice = volume * price;
    sumVolumePrice += volumePrice;
    double profit = position.Profit();
    sumProfit += profit;
    currentStep++;
  }

  double averagePrice = sumVolume > 0 ? sumVolumePrice/sumVolume : 0;

// Calculate Next open volume
  nextOpenVolume = currentStep < maximumStep ? NormalizeDouble( baseVolume + (baseVolume * currentStep * multiplierVolume), Digits()) : 0.0;
  nextSumVolume = currentStep < maximumStep ? sumVolume + nextOpenVolume : 0;

  Print("- Current Step: " + IntegerToString(currentStep));
  Print("- Sum Volume: " + DoubleToString(sumVolume, 2));
  Print("- Sum (Volume x Price): " + DoubleToString(sumVolumePrice, 2));
  Print("- Average Price: " + DoubleToString(averagePrice, 2));
  Print("- Sum Profit: " + DoubleToString(sumProfit, 2));
  Print("- Next Open Volume: " + DoubleToString(nextOpenVolume, 2) + " lot");
  Print("- Next Sum Volume: " + DoubleToString(nextSumVolume, 2) + " lot");

  if(sumVolume <= 0) {
    minimumAskPrice = 0.0;
    takeProfitPrice = 0.0;
    return;
  }

  double minimumDistancePercentage = (deviationStep + ((currentStep-1) * deviationStep * multiplierStep));
  double minimumDistancePrice = averagePrice * minimumDistancePercentage / 100;
  minimumAskPrice = NormalizeDouble(averagePrice - minimumDistancePrice, Digits());
  double profit = targetProfit*sumVolume;
  takeProfitPrice = NormalizeDouble(averagePrice + profit, Digits());

  Print("- Take Profit Price: " + DoubleToString(takeProfitPrice, 2));
  Print("- Minimum Distance to Open New Trade: " + DoubleToString(minimumDistancePercentage, 2) + "% = " + DoubleToString(minimumDistancePrice, 2) );
  Print("- Minimum Ask Price to Open New Trade: " + DoubleToString(minimumAskPrice, 2));

  adjustTakeProfit();
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
void adjustTakeProfit() {
  Print("# Adjust Take Profit");
  double ask = SymbolInfoDouble(Symbol(), SYMBOL_ASK);
  if(takeProfitPrice < ask) {
    Print("- Current Take Profit: " + DoubleToString(takeProfitPrice, 2));
    Print("- Ask: " + DoubleToString(ask, 2));
    takeProfitPrice = NormalizeDouble(ask + (nextSumVolume*targetProfit), 2);
    Print("- Adjust Take Profit: " + DoubleToString(takeProfitPrice, 2));
  }

  for(int i = (PositionsTotal()-1); i >= 0; i--) {
    bool isSelected = position.SelectByIndex(i);
    if(!isSelected) continue;
    ulong ticket = position.Ticket();
    double currentTakeProfit = position.TakeProfit();
    if(currentTakeProfit == takeProfitPrice) continue;
    if(trade.PositionModify(ticket, 0.0, takeProfitPrice)) {
      Print("- Ticket #" + IntegerToString(ticket));
      Print("- New Take Profit Price: " + DoubleToString(takeProfitPrice));
    }
  }
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
double maximumVolume() {
  double totalVolume = 0;
  for(int i = 0; i < maximumStep; i++) {
    double volume = baseVolume * (i * multiplierVolume);
    totalVolume += volume;
  }
  return totalVolume;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool priceActionTrigger() {
  for(int i=1; i<= greenPeriod; i++) {
    double open = iOpen(Symbol(), timeframe, i);
    double close = iClose(Symbol(), timeframe, i);
    if(open > close) {
      // Open > Close = red candle, return false
      return false;
    }
  }
  for(int i=(greenPeriod+1); i<= totalPeriod; i++) {
    double open = iOpen(Symbol(), timeframe, i);
    double close = iClose(Symbol(), timeframe, i);
    if(open < close) {
      // Open < Close = gren candle, return false
      return false;
    }
  }
// Green = greenPeriod and Red = redPeriod true
  return true;
}

//+------------------------------------------------------------------+
//|                                                                  |
//+------------------------------------------------------------------+
bool isNewBar() {
  static datetime lastBar;
  return lastBar != (lastBar = iTime(_Symbol, timeframe, 0));
}
//+------------------------------------------------------------------+
