program Sync2Indicia;

uses
  Forms,
  main in 'main.pas' {frmMain},
  Hashes in 'Hashes.pas',
  uLkJSON in 'uLkJSON.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
