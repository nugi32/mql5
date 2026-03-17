import talib
import numpy as np


class Indicators:

    # =========================
    # TREND INDICATORS
    # =========================

    @staticmethod
    def sma(close, period=14):
        return talib.SMA(close, timeperiod=period)

    @staticmethod
    def ema(close, period=14):
        return talib.EMA(close, timeperiod=period)

    @staticmethod
    def wma(close, period=14):
        return talib.WMA(close, timeperiod=period)

    @staticmethod
    def dema(close, period=14):
        return talib.DEMA(close, timeperiod=period)

    @staticmethod
    def tema(close, period=14):
        return talib.TEMA(close, timeperiod=period)

    @staticmethod
    def trima(close, period=14):
        return talib.TRIMA(close, timeperiod=period)

    @staticmethod
    def kama(close, period=14):
        return talib.KAMA(close, timeperiod=period)

    @staticmethod
    def macd(close, fast=12, slow=26, signal=9):
        macd, signal_line, hist = talib.MACD(
            close,
            fastperiod=fast,
            slowperiod=slow,
            signalperiod=signal
        )
        return macd, signal_line, hist

    @staticmethod
    def adx(high, low, close, period=14):
        return talib.ADX(high, low, close, timeperiod=period)

    @staticmethod
    def plus_di(high, low, close, period=14):
        return talib.PLUS_DI(high, low, close, timeperiod=period)

    @staticmethod
    def minus_di(high, low, close, period=14):
        return talib.MINUS_DI(high, low, close, timeperiod=period)

    # =========================
    # MOMENTUM INDICATORS
    # =========================

    @staticmethod
    def rsi(close, period=14):
        return talib.RSI(close, timeperiod=period)

    @staticmethod
    def stoch(high, low, close,
              fastk_period=5,
              slowk_period=3,
              slowd_period=3):
        slowk, slowd = talib.STOCH(
            high, low, close,
            fastk_period=fastk_period,
            slowk_period=slowk_period,
            slowk_matype=0,
            slowd_period=slowd_period,
            slowd_matype=0
        )
        return slowk, slowd

    @staticmethod
    def cci(high, low, close, period=14):
        return talib.CCI(high, low, close, timeperiod=period)

    @staticmethod
    def willr(high, low, close, period=14):
        return talib.WILLR(high, low, close, timeperiod=period)

    @staticmethod
    def roc(close, period=10):
        return talib.ROC(close, timeperiod=period)

    @staticmethod
    def momentum(close, period=10):
        return talib.MOM(close, timeperiod=period)

    # =========================
    # VOLATILITY INDICATORS
    # =========================

    @staticmethod
    def atr(high, low, close, period=14):
        return talib.ATR(high, low, close, timeperiod=period)

    @staticmethod
    def natr(high, low, close, period=14):
        return talib.NATR(high, low, close, timeperiod=period)

    @staticmethod
    def bollinger_bands(close,
                        period=20,
                        dev_up=2,
                        dev_down=2):
        upper, middle, lower = talib.BBANDS(
            close,
            timeperiod=period,
            nbdevup=dev_up,
            nbdevdn=dev_down,
            matype=0
        )
        return upper, middle, lower

    # =========================
    # VOLUME INDICATORS
    # =========================

    @staticmethod
    def obv(close, volume):
        return talib.OBV(close, volume)

    @staticmethod
    def ad(high, low, close, volume):
        return talib.AD(high, low, close, volume)

    @staticmethod
    def adosc(high, low, close, volume,
              fast=3, slow=10):
        return talib.ADOSC(
            high, low, close, volume,
            fastperiod=fast,
            slowperiod=slow
        )

    # =========================
    # PRICE TRANSFORM
    # =========================

    @staticmethod
    def typical_price(high, low, close):
        return talib.TYPPRICE(high, low, close)

    @staticmethod
    def weighted_close(high, low, close):
        return talib.WCLPRICE(high, low, close)