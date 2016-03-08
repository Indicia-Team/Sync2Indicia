object frmMain: TfrmMain
  Left = 192
  Top = 124
  Width = 298
  Height = 137
  Caption = 'Recorder Indicia Synch'
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'MS Sans Serif'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object lblProgress: TLabel
    Left = 8
    Top = 40
    Width = 36
    Height = 13
    Caption = 'Waiting'
  end
  object lblFile: TLabel
    Left = 8
    Top = 16
    Width = 3
    Height = 13
  end
  object ProgressBar: TProgressBar
    Left = 8
    Top = 64
    Width = 265
    Height = 17
    TabOrder = 0
  end
  object IdHTTP1: TIdHTTP
    MaxLineAction = maException
    ReadTimeout = 0
    AllowCookies = True
    ProxyParams.BasicAuthentication = False
    ProxyParams.ProxyPort = 0
    Request.ContentLength = -1
    Request.ContentRangeEnd = 0
    Request.ContentRangeStart = 0
    Request.ContentType = 'text/html'
    Request.Accept = 'text/html, */*'
    Request.BasicAuthentication = False
    Request.UserAgent = 'Mozilla/3.0 (compatible; Indy Library)'
    HTTPOptions = [hoForceEncodeParams]
    Left = 152
  end
end
