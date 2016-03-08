unit main;

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, IdBaseComponent, IdComponent, IdTCPConnection,
  IdTCPClient, IdHTTP, IdMultipartFormData, AdoDb, Registry, ComCtrls, SHFolder;

const
  WM_START = WM_APP + 1;

type
  TfrmMain = class(TForm)
    IdHTTP1: TIdHTTP;
    ProgressBar: TProgressBar;
    lblProgress: TLabel;
    lblFile: TLabel;
  private
    FFixedValues: TStringList;
    FMappings: TStringList;
    FQuery: TStringList;
    FExistingRecordMatchFields: TStringList;
    FExistingRecordCopyFields: TStringList;
    FExistingRecordAdditionalFilters: TStringList;
    FMatchValues: TStringList;
    FModel: string;
    FWebsiteID: integer;
    FWebsitePassword: string;
    FLastRunDate: TDateTime;
    FConnection: TADOConnection;
    FExistingRecords: TStringList;
    FReadAuthToken: string;
    FWriteAuthToken: string;
    FReadNonce: string;
    FWriteNonce: string;
    FUploadedFile: string;
    FSettingsFolder: string;
    FWarehouseUrl: string;
    FErrors: string;
    procedure SetWebsiteID(const Value: integer);
    procedure SetWebsitePassword(const Value: string);
    procedure SetLastRunDate(const Value: TDateTime);
    procedure Connect;
    procedure Disconnect;
    function GetRecorderConnectionString: string;
    procedure FindExistingRecords(rs: _Recordset);
    procedure CreateFileToUpload(rs: _Recordset);
    function GetWindowsTempDir: String;
    procedure UploadFile;
    procedure UploadMetadata;
    procedure UploadData;
    procedure SetStatus(const status: string);
    function GetFolder(csidl: Integer): String;
    procedure LoadWarehouseSettings;
    procedure SetWarehouseUrl(const Value: string);
    procedure ProcessFile(const AFile: string);
    procedure ProcessFiles;
    procedure Process;
    procedure WMStart(var msg: TMessage); message WM_START;
    function QueryLocalData: _Recordset;
    procedure MatchPotentialExistingRecords(const keys: string);
    function UrlEncode(const ASrc: string): string;
    procedure CheckUploadResult;
    { Private declarations }
  public
    { Public declarations }
    constructor Create(AOwner: TComponent); override;
    destructor destroy; override;
    property WarehouseUrl: string read FWarehouseUrl write SetWarehouseUrl;
    property WebsiteID: integer read FWebsiteID write SetWebsiteID;
    property WebsitePassword: string read FWebsitePassword write SetWebsitePassword;
    property LastRunDate: TDateTime read FLastRunDate write SetLastRunDate;
  end;

var
  frmMain: TfrmMain;

implementation

uses Hashes, uLkJSON, ADOInt;

{$R *.dfm}

procedure TfrmMain.Process;
var
  request: TIdMultiPartFormDataStream;
  response: string;
  stream: TStringStream;
  nonces: TlkJSONbase;
  rs: _Recordset;
begin
  request := TIdMultiPartFormDataStream.Create;
  try
    SetStatus('Authenticating');
    request.AddFormField('website_id', IntToStr(WebsiteId));
    response := idHttp1.Post(FWarehouseUrl + '/services/security/get_read_write_nonces', request);
    nonces := TlkJSON.ParseText(response);
    stream := TStringStream.Create(nonces.Field['read'].Value + ':' + WebsitePassword);
    FReadAuthToken := CalcHash(stream, haSHA1);
    FReadNonce := nonces.Field['read'].Value;
    stream.free;
    stream := TStringStream.Create(nonces.Field['write'].Value + ':' + WebsitePassword);
    FWriteAuthToken := CalcHash(stream, haSHA1);
    FWriteNonce := nonces.Field['write'].Value;
    stream.free;
    rs := QueryLocalData;
    if (rs.RecordCount<>0) then begin
      FindExistingRecords(rs);
      CreateFileToUpload(rs);
      UploadFile;
      UploadMetadata;
      UploadData;
      DeleteFile(GetWindowsTempDir + 'indiciaUpload.csv');
    end;
  finally
    request.free;
  end;
end;

function TfrmMain.QueryLocalData: _Recordset;
var
  year, month, day: word;
  dateStr: string;
  query: string;
  i: integer;
begin
  DecodeDate(LastRunDate, year, month, day);
  dateStr := IntToStr(Year) + '-' + IntToStr(month) + '-' + IntToStr(day);
  query := StringReplace(FQuery.Text, '#lastrun#', dateStr, [rfReplaceAll]);
  FConnection.CursorLocation := clUseClient;
  // For SQL Server we want some set options. This code skips the options for Access, probably
  // need to cover other connection types here as well.
  if Pos('Jet OLEDB', FConnection.ConnectionString)=0 then
    query := 'SET NOCOUNT ON; SET ANSI_WARNINGS OFF; ' + #13#10 + query;
  result := FConnection.Execute(query);
  if FConnection.Errors.Count>0 then begin
    for i := 0 to FConnection.Errors.Count-1 do
      ShowMessage(FConnection.Errors.Item[i].Source + ' - ' + FConnection.Errors.Item[i].Description);
  end;
end;

procedure TfrmMain.CreateFileToUpload(rs: _Recordset);
var
  fileContent, matchData: TStringList;
  row: string;
  i, idx: integer;
begin
  SetStatus('Building upload file');
  fileContent := TStringList.Create;
  try
    rs.MoveFirst;
    row := rs.Fields[0].Name;
    for i := 1 to rs.Fields.Count-1 do
      if not SameText('new', rs.Fields[i].Name) then
        row := row + ',' + rs.Fields[i].Name;
    // add data to the CSV file for joining to existing records
    for i := 0 to FExistingRecordCopyFields.Count-1 do
      row := row + ',' + FExistingRecordCopyFields.ValueFromIndex[i];
    fileContent.Add(row);
    while not (rs.Eof) do begin
      row := '"' + VarToStr(rs.Fields[0].Value) + '"';
      for i := 1 to rs.Fields.Count-1 do
        if not SameText('new', rs.Fields[i].Name) then
          row := row + ',"' + VarToStr(rs.Fields[i].Value) + '"';
      // look for any info on a match to an existing record
      idx := FMatchValues.IndexOf(rs.Fields[FExistingRecordMatchFields.Values['localKeyField']].Value);
      // get the stringlist which contains match values for this row
      if idx>-1 then begin
        matchData := TStringList(FMatchValues.Objects[idx]);
        for i := 0 to FExistingRecordCopyFields.Count-1 do begin
          // copy the values that join this record to an existing record into the csv
          row := row + ',' + matchData.Values[FExistingRecordCopyFields.ValueFromIndex[i]];
        end;
      end
      else
        for i := 0 to FExistingRecordCopyFields.Count-1 do
          row := row + ',';
      fileContent.Add(row);
      rs.MoveNext;
    end;
    fileContent.SaveToFile(GetWindowsTempDir + 'indiciaUpload.csv');
  finally
    fileContent.Free;
  end;
end;

procedure TfrmMain.UploadFile;
var
  stream: TIdMultiPartFormDataStream;
begin
  SetStatus('Uploading data file');
  stream := TIdMultiPartFormDataStream.Create;
  stream.AddFile('media_upload', GetWindowsTempDir + 'indiciaUpload.csv', 'csv');
  stream.AddFormField('auth_token', FWriteAuthToken);
  stream.AddFormField('nonce', FWriteNonce);
  stream.AddFormField('persist_auth', 'true');
  stream.AddFormField('website_id', IntToStr(FWebsiteId));
  try
    FUploadedFile := IdHTTP1.Post(FWarehouseUrl + '/services/import/upload_csv', stream);
    // TODO: error check the response
  finally
    stream.Free;
  end;
end;

(**
 * Upload the various settings that apply to every row.
 *)
procedure TfrmMain.UploadMetadata;
var
  response: string;
  data: TIdMultiPartFormDataStream;
  i: integer;
  str: string;
begin
  SetStatus('Uploading settings');
  data := TIdMultiPartFormDataStream.Create;
  try
    for i := 0 to FFixedValues.Count-1 do
      str := str + '"' + FFixedValues.Names[i] + '":"' + FFixedValues.ValueFromIndex[i] + '",';
    str := Copy(str, 1, Length(str)-1);
    data.AddFormField('settings', '{' + str + '}');
    // now do the mappings -> JSON
    str := '';
    for i := 0 to FMappings.Count-1 do
      str := str + '"' + FMappings.Names[i] + '":"' + FMappings.ValueFromIndex[i] + '",';
    // the mappings must also contain any fields used to link to existing records
    for i := 0 to FExistingRecordCopyFields.Count-1 do
      str := str + '"' + FExistingRecordCopyFields.ValueFromIndex[i] + '":"' + FExistingRecordCopyFields.ValueFromIndex[i] + '",';
    str := Copy(str, 1, Length(str)-1);
    data.AddFormField('mappings', '{' + str + '}');
    data.AddFormField('auth_token', FWriteAuthToken);
    data.AddFormField('nonce', FWriteNonce);
    data.AddFormField('website_id', IntToStr(FWebsiteId));
    data.AddFormField('uploaded_csv', FUploadedFile);
    response := IdHttp1.Post(FWarehouseUrl + '/services/import/cache_upload_metadata?uploaded_csv='+FUploadedFile, data);
    if response<>'OK' then
      raise Exception.Create(response);
  finally
    data.free;
  end;
end;

procedure TfrmMain.UploadData;
var
  offset, filepos, limit: integer;
  request, response: string;
  parsed: TlkJSONbase;
begin
  SetStatus('Uploading data');
  limit := 50;
  offset := 0;
  filepos := 0;
  repeat
    request := FWarehouseUrl + '/services/import/upload?model='+FModel+
        '&uploaded_csv='+FUploadedFile+
        '&limit='+IntToStr(limit)+
        '&offset='+IntToStr(offset)+
        '&filepos='+IntToStr(filepos);
    response := IdHttp1.Get(request);
    parsed := TlkJSON.ParseText(response);
    filepos := parsed.Field['filepos'].Value;
    offset := offset + parsed.Field['uploaded'].Value;
    progressBar.Position := parsed.Field['progress'].Value;
    Application.ProcessMessages;
  until parsed.Field['uploaded'].Value < limit;
  CheckUploadResult;
  SetStatus('Upload complete');
end;

procedure TfrmMain.CheckUploadResult;
var
  request, response: string;
  parsed: TlkJSONbase;
begin
  request := FWarehouseUrl + '/services/import/get_upload_result?uploaded_csv=' + FUploadedFile +
        '&auth_token=' + FReadAuthToken +
        '&nonce=' + FReadNonce;
  response := IdHttp1.Get(request);
  parsed := TlkJSON.ParseText(response);
  if parsed<>nil then begin
    if parsed.Field['problems']<>nil then begin
      if parsed.Field['problems'].Value<>0 then begin
        FErrors := VarToStr(parsed.Field['problems'].Value) +
          ' records failed to upload. Further information in the file ' + parsed.Field['file'].Value;
      end;
      exit;
    end;
  end;
  // shouldn't get here
  FErrors := 'An error occurred when retrieving the upload response.';
end;

procedure TfrmMain.Connect;
var
  fileContent: TStringList;
begin
  FConnection := TADOConnection.Create(nil);
  if FileExists(FSettingsFolder + 'LocalConnectionString.txt') then begin
    fileContent := TStringList.Create;
    try
      fileContent.LoadFromFile(FSettingsFolder + 'LocalConnectionString.txt');
      FConnection.ConnectionString := fileContent.Text;
    finally
      fileContent.free;
    end;
  end else
    FConnection.ConnectionString := GetRecorderConnectionString;
  FConnection.Open;
end;

constructor TfrmMain.Create(AOwner: TComponent);
begin
  inherited;
  PostMessage(self.handle, WM_START, 0, 0);
end;

procedure TfrmMain.WMStart(var msg: TMessage);
begin
  // Find the settings folder, under my documents or public documents if that does not exist.
  FSettingsFolder := GetFolder(CSIDL_PERSONAL) + 'Sync2Indicia\';
  if not DirectoryExists(FSettingsFolder) then
    FSettingsFolder := GetFolder(CSIDL_COMMON_DOCUMENTS) + 'Sync2Indicia\';
  if not DirectoryExists(FSettingsFolder) then
    raise Exception.Create('The Sync2Indicia folder does not exist in My Documents or Public Documents');
  LoadWarehouseSettings;
  Connect;
  ProcessFiles;
  Close;
end;

procedure TfrmMain.ProcessFiles;
var
  sr: TSearchRec;
begin
  if FindFirst(FSettingsFolder + '*.link', 0, sr) = 0 then begin
    repeat
      lblFile.Caption := 'Processing '+sr.Name;
      ProcessFile(sr.Name);
    until FindNext(sr)<>0;
    FindClose(sr);
  end;
end;


procedure TfrmMain.ProcessFile(const AFile: string);
type
  TState = (sSeek, sFixedValues, sMappings, sQuery, sExistingRecordMatchFields, sExistingRecordAdditionalFilters, sExistingRecordCopyFields);
var
  linkFile: TStringList;
  i: integer;
  state: TState;
  key, value, dateStr: string;
  runDate: TDateTime;
  logFile: TStringlist;
begin
  runDate := now;
  FFixedValues := TStringList.Create;
  FMappings := TStringList.Create;
  FQuery := TStringList.Create;
  FExistingRecordMatchFields := TStringList.Create;
  FExistingRecordCopyFields := TStringList.Create;
  FExistingRecordAdditionalFilters := TStringList.Create;
  FMatchValues := TStringList.Create;
  linkFile := TStringList.Create;
  logFile := TStringList.Create;
  if FileExists(FSettingsFolder + Copy(AFile, 1, length(AFile)-4) + 'log') then begin
    logFile.LoadFromFile(FSettingsFolder + Copy(AFile, 1, length(AFile)-4) + 'log');
    dateStr := logFile[logFile.count-1];
    if Copy(dateStr, 1, 6) = 'ERROR:' then
      dateStr := logFile[logFile.count-2];
    LastRunDate := StrToDate(dateStr);
  end else
    // default - anything from last 100 years will do
    LastRunDate := now - 365 * 100;
  try
    if not FileExists(FSettingsFolder + AFile) then begin
      ShowMessage('Cannot find file ' + FSettingsFolder + AFile);
      Abort;
    end;
    linkFile.LoadFromFile(FSettingsFolder + AFile);
    if linkFile.Values['direction']<>'upload' then
      ShowMessage('Only direction=upload link files are supported')
    else begin
      FModel := linkFile.Values['model'];
      // a simple state machine to parse the link file
      state := sSeek;
      for i := 0 to linkFile.Count-1 do begin
        // lines starting # are comments.
        if (Copy(linkFile[i], 1, 1)='#') then
          continue;
        if SameText(Trim(linkFile[i]), '=fixedvalues=') then
          state := sFixedValues
        else if SameText(Trim(linkFile[i]), '=mappings=') then
          state := sMappings
        else if SameText(Trim(linkFile[i]), '=query=') then
          state := sQuery
        else if SameText(Trim(linkFile[i]), '=existingrecordmatchfields=') then
          state := sExistingRecordMatchFields
        else if SameText(Trim(linkFile[i]), '=existingrecordadditionalfilters=') then
          state := sExistingRecordAdditionalFilters
        else if SameText(Trim(linkFile[i]), '=existingrecordcopyfields=') then
          state := sExistingRecordCopyFields
        else if state in [sFixedValues, sMappings, sExistingRecordMatchFields, sExistingRecordAdditionalFilters, sExistingRecordCopyFields] then begin
          key := Trim(Copy(linkFile[i], 1, Pos('=', linkFile[i])-1));
          value := Trim(Copy(linkFile[i], Pos('=', linkFile[i]) + 1, Length(linkFile[i])));
          if (state=sFixedValues) then
            FFixedValues.Values[key]:=value
          else if (state=sMappings) then
            FMappings.Values[key]:=value
          else if (state=sExistingRecordMatchFields) then
            FExistingRecordMatchFields.Values[key]:=value
          else if (state=sExistingRecordAdditionalFilters) then
            FExistingRecordAdditionalFilters.Values[key]:=value
          else if (state=sExistingRecordCopyFields) then
            FExistingRecordCopyFields.Values[key]:=value
        end
        else if (state=sQuery) then
          FQuery.Add(linkFile[i]);
      end;
      FErrors := '';
      Process;
      logFile.Add(DateToStr(runDate));
      if FErrors <> '' then
        logFile.Add('ERROR: ' + FErrors);
      logFile.SaveToFile(FSettingsFolder + Copy(AFile, 1, length(AFile)-4) + 'log');
    end;
  finally
    linkFile.Free;
    logFile.Free;
    FreeAndNil(FFixedValues);
    FreeAndNil(FMappings);
    FreeAndNil(FQuery);
    FreeAndNil(FExistingRecordMatchFields);
    FreeAndNil(FExistingRecordCopyFields);
    FreeAndNil(FExistingRecordAdditionalFilters);
    for  i:= 0 to FMatchValues.Count-1 do
      FMatchValues.Objects[i].Free;
    FreeAndNil(FMatchValues);
  end;
end;

destructor TfrmMain.destroy;
begin
  Disconnect;
  FExistingRecords.Free;
  FFixedValues.Free;
  inherited;
end;

procedure TfrmMain.Disconnect;
begin
  FConnection.Close;
  FConnection.Free;
end;

(**
 * Looks through the local data recordset to find any records which already exist on
 * the warehouse.
 *)
procedure TfrmMain.FindExistingRecords(rs: _Recordset);
var
  hasNewFlag: boolean;
  i: integer;
  keys: string;
begin
  if rs.RecordCount>0 then begin
    // a stringlist to keep chunks of keys, with a certain
    hasNewFlag := false; // default unless we find a field called new
    // search for a flag in the data indicating which records are new since last upload
    for i := 0 to rs.Fields.Count-1 do
      hasNewFlag := hasNewFlag or SameText(rs.Fields[i].Name, 'new');
    rs.MoveFirst;
    keys := '';
    // find all the matching keys for the records that might be existing
    while not rs.EOF do begin
      if hasNewFlag then
        if rs.Fields['new'].Value=1 then begin
          // can skip any records we know are new since the last sync
          rs.MoveNext;
          Continue;
        end;
      if keys<>'' then keys := keys + ',';
      keys := keys + '"' + rs.Fields[FExistingRecordMatchFields.Values['localKeyField']].Value + '"';
      if length(keys)>1000 then begin
        // Match a chunk of potential records.
        MatchPotentialExistingRecords(keys);
        keys := '';
      end;
      rs.MoveNext;
    end;
    // The list of keys we have now are the localKeyField values for every record that might
    // already exist on the warehouse. Find which ones actually do.
    if keys<>'' then
      MatchPotentialExistingRecords(keys);
  end;
end;

(**
 * Takes a list of record keys for local records which might already exist on the warehouse
 * and works out which ones do really match.
 *)
procedure TfrmMain.MatchPotentialExistingRecords(const keys: string);
var
  existing, row, matchFieldColumnIndexes, matchInfo: TStringList;
  query, response, indiciaKeyField: string;
  i, j, indiciaKeyFieldIdx: integer;
  request: string;
begin
  // todo: pagination of the response
  indiciaKeyField := FExistingRecordMatchFields.Values['indiciaKeyField'];
  query := '{"in":["'+indiciaKeyField+'",[' + keys + ']]}';
  request := FWarehouseUrl + '/services/data/' + FModel +
      '?query=' + urlencode(query) +
      '&auth_token=' + FReadAuthToken +
      '&nonce=' + FReadNonce +
      '&mode=csv' +
      '&view=detail';
  for i := 0 to FExistingRecordAdditionalFilters.Count-1 do
    request := request + '&' + FExistingRecordAdditionalFilters.Names[i] + '=' + FExistingRecordAdditionalFilters.Values[FExistingRecordAdditionalFilters.Names[i]];
  response := idHttp1.Get(request);
  existing := TStringList.Create;
  row := TStringList.Create;
  matchFieldColumnIndexes := TStringList.Create;
  try
    indiciaKeyFieldIdx := -1;
    existing.Text := response;
    if existing.Count>0 then begin
      row.CommaText := existing[0];
      // look in the first row of the response from Indicia for the ID fields we are supposed to be joining to
      for i := 0 to row.Count-1 do begin
        if FExistingRecordCopyFields.IndexOfName(row[i])>-1 then begin
          // make a note of the submission field we need to set for each match, plus the index
          // of the csv field we need to set it to.
          matchFieldColumnIndexes.Values[FExistingRecordCopyFields.Values[row[i]]] := IntToStr(i);
        end;
        // also make a note of the csv field index that we are using as a PK
        if row[i]=indiciaKeyField then
          indiciaKeyFieldIdx := i;
      end;
      if indiciaKeyFieldIdx=-1 then
        raise Exception.Create('The indicia key field could not be found in the warehouse response');
      // now loop through the existing records returned from the warehouse so we can store the
      // join information required later
      for i := 1 to existing.Count-1 do begin
        row.CommaText := existing[i];
        // create an object that will store the join info for each matched row
        matchInfo := TStringList.Create;
        // loop through the fields that need to be copied into each existing record
        // from the local database to associate them to the warehouse record
        for j := 0 to FExistingRecordCopyFields.Count-1 do begin
          if j>=FExistingRecordCopyFields.Count then
            ShowMessage('j is too high - ' + IntToStr(j) + char(13) + char(10) +
              FExistingRecordCopyFields.GetText);

          if StrToInt(matchFieldColumnIndexes.Values[FExistingRecordCopyFields.ValueFromIndex[j]])>=row.count then
            ShowMessage('row index ' + matchFieldColumnIndexes.Values[FExistingRecordCopyFields.ValueFromIndex[j]] +
                ' not found. ' + char(13)+char(10)+row.GetText);

          matchInfo.Values[FExistingRecordCopyFields.ValueFromIndex[j]] :=
              row[StrToInt(matchFieldColumnIndexes.Values[FExistingRecordCopyFields.ValueFromIndex[j]])];
        end;
        // now we have a string list that defines each field that will need a value added to it
        // (normally an id field) for the row. So, save this for later use when we are building the
        // upload CSV file, as this data needs to be spliced into the CSV file for each matching row.
        FMatchValues.AddObject(row[indiciaKeyFieldIdx], matchInfo);
      end;
    end;
  finally
    existing.Free;
    row.Free;
    matchFieldColumnIndexes.Free;
  end;
end;

function TfrmMain.UrlEncode(const ASrc: string): string;
var
  i: Integer;
const
  UnsafeChars = ['*','#','%','<','>',' ','[',']'];
begin
  Result := '';
  for i := 1 to Length(ASrc) do
  begin
    if (ASrc [i] in UnsafeChars) or (not Ord(ASrc[i]) in [33..128]) then begin
      Result := Result + '%' + IntToHex(Ord(ASrc[i]), 2);
    end else begin
      Result := Result + ASrc[i];
    end;
  end;
end;

function TfrmMain.GetRecorderConnectionString: string;
var
  security: string;
  reg: TRegistry;
begin
  reg := TRegistry.Create;
  try
    reg.RootKey := HKEY_LOCAL_MACHINE;
    reg.OpenKeyReadOnly('SOFTWARE\Dorset Software\Recorder 6\');

  finally
  end;
  if (reg.ReadBool('Trusted Security')) then
    security := 'Integrated Security=SSPI;'
  else
    security := 'User ID=NBNUser;password=NBNPassword;';
  result := 'Provider=SQLOLEDB.1;' + security +
      'Persist Security Info=False;Initial Catalog=' + reg.ReadString('Database Name')+';' +
      'Data Source=' + reg.ReadString('Server Name');
end;

procedure TfrmMain.SetLastRunDate(const Value: TDateTime);
begin
  FLastRunDate := Value;
end;

procedure TfrmMain.SetWebsiteID(const Value: integer);
begin
  FWebsiteID := Value;
end;

procedure TfrmMain.SetWebsitePassword(const Value: string);
begin
  FWebsitePassword := Value;
end;

function TfrmMain.GetWindowsTempDir: String;
var
  BufLen: Integer;
  TempPath: AnsiString;
begin
  BufLen := GetTempPath(0, PChar(TempPath));

  if BufLen > 0 then
  begin
    SetLength(TempPath, BufLen);
    BufLen := GetTempPath(BufLen, PChar(TempPath));
  end;

  if BufLen = 0 then
    RaiseLastOSError;

  Result := Copy(TempPath, 1, BufLen);  // removes zero terminator
end;  // GetWindowsTempDir

procedure TfrmMain.SetStatus(const status: string);
begin
  lblProgress.Caption := status + '...';
  Refresh;
end;

function TfrmMain.GetFolder(csidl: Integer): String;
var
  i: Integer;
begin
  SetLength(Result, MAX_PATH);
  SHGetFolderPath(0, csidl, 0, 0, PChar(Result));
  i := Pos(#0, Result);
  if i > 0 then begin
    SetLength(Result, Pred(i));
    Result := IncludeTrailingPathDelimiter(Result);
  end;
end;

procedure TfrmMain.LoadWarehouseSettings;
var
  settingsFile: TStringList;
begin
  settingsFile := TStringList.Create;
  if not FileExists(FSettingsFolder + 'Warehouse.txt') then begin
    ShowMessage('Cannot find file ' + FSettingsFolder + 'Warehouse.txt. This is required to define ' +
        'a connection to the Indicia warehouse.');
    Abort;
  end;
  try
    settingsFile.LoadFromFile(FSettingsFolder + 'Warehouse.txt');
    WarehouseUrl := settingsFile.Values['warehouse_url'];
    WebsiteId := StrToInt(settingsFile.Values['website_id']);
    WebsitePassword := settingsFile.Values['website_password'];
  finally
    settingsFile.Free;
  end;
end;

procedure TfrmMain.SetWarehouseUrl(const Value: string);
begin
  if Copy(Value, Length(Value)-8, 255)<>'index.php' then begin
    ShowMessage('The Warehouse URL setting in the warehouse.txt file does not appear to be correct. It '+
        'should be the full path to the warehouse URL including the index.php part.');
  end;
  FWarehouseUrl := Value;
end;

end.
