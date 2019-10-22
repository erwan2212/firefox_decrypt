program ffdecrypt;

{$APPTYPE CONSOLE}

uses
  Windows,SHFolder,sysutils,classes,{$ifdef fpc}base64,{$endif fpc}
  SQLite3Wrap,
  uLkJSON;
  //idcoder,IdCoderMIME; //indy10 //but can use FPC base64 unit


type
  TSECItem =  record //stay away from packed...
  SECItemType: dword;
  SECItemData: pansichar;
  SECItemLen: dword;
  end;
  PSECItem = ^TSECItem;

{$ifndef fpc} //
    tbytes=array of byte;
  {$endif fpc}

  //typedef enum SECItemType
    const
    siBuffer = 0;
    siClearDataBuffer = 1;
    siCipherDataBuffer = 2;
    siDERCertBuffer = 3;
    siEncodedCertBuffer = 4;
    siDERNameBuffer = 5;
    siEncodedNameBuffer = 6;
    siAsciiNameString = 7;
    siAsciiString = 8;
    siDEROID = 9;
    siUnsignedInteger = 10;
    siUTCTime = 11;
    siGeneralizedTime = 12 ;


var
  NSS_Init                                               : function(configdir: pchar): dword; cdecl;
  ATOB_AsciiToData                                       : function(input:pchar;var lenp:uint):pointer;cdecl;
  //PL_Base64Decode                                        : function (input:pchar; srclen:pdword; dest:pchar):pointer; cdecl;
  NSSBase64_DecodeBuffer                                 : function(arenaOpt: pointer; outItemOpt: PSECItem; inStr: pchar; inLen: dword): dword; cdecl;
  PK11_GetInternalKeySlot                                : function: pointer; cdecl;
  PK11_Authenticate                                      : function(slot: pointer; loadCerts: boolean; wincx: pointer): dword; cdecl;
  PK11SDR_Decrypt                                        : function(data: PSECItem;  res: PSECItem; cx: pointer): dword; cdecl;
  GetUserProfileDirectory                                : function(hToken: THandle; lpProfileDir: pchar; var lpcchSize: dword): longbool; stdcall;
  NSS_Shutdown                                           : procedure; cdecl;
  PK11_FreeSlot                                          : procedure(slot: pointer); cdecl;

{
  function Base64Decode(const EncodedText: string;var lenp:uint): TBytes;
  var
    DecodedStm: TBytesStream;
    Decoder: TIdDecoderMIME;
  begin
    Decoder := TIdDecoderMIME.Create(nil);
    try
      DecodedStm := TBytesStream.Create;
      try
        Decoder.DecodeBegin(DecodedStm);
        Decoder.Decode(EncodedText);
        Decoder.DecodeEnd;
        lenp:=DecodedStm.Size ;
        setlength(result,DecodedStm.Size);
        Result := DecodedStm.Bytes;
      finally
        DecodedStm.Free;
      end;
    finally
      Decoder.Free;
    end;
  end;
}



function FolderPath(folder : integer) : string;
const
SHGFP_TYPE_CURRENT = 0;
var
  path: array [0..MAX_PATH] of char;
begin
if SUCCEEDED(SHGetFolderPath(0,folder,0,SHGFP_TYPE_CURRENT,@path[0])) then
Result := path
else
Result := '';
end;

procedure decrypt(value:string;var decrypted:string);
var
EncryptedSECItem,DecryptedSECItem                       : TSECItem;
//DecryptedSECItem:PSECItem;
p:pchar;
output:string;
lenp:uint;
bytes:tbytes;
begin
fillchar(EncryptedSECItem,sizeof(TSECItem),0);
fillchar(DecryptedSECItem,sizeof(TSECItem),0);
//DecryptedSECItem :=allocmem(sizeof(tsecitem));
//writeln('decrypt 0');
if nativeuint(@NSSBase64_DecodeBuffer) <>0
   then NSSBase64_DecodeBuffer(nil, @EncryptedSECItem, pchar(Value), Length(Value))
   else
   begin
   //writeln(value);
   //writeln(length(value));
   lenp:=0;

   {
   //using legacy ATOB_AsciiToData //to eventually keep compatibility with good ol' delphi7
   p:=ATOB_AsciiToData(pchar(value),lenp);
   EncryptedSECItem.SECItemData :=p;
   EncryptedSECItem.SECItemLen :=lenp;
   if EncryptedSECItem.SECItemData=nil then writeln('EncryptedSECItem.SECItemData=nil');
   //writeln(strpas(EncryptedSECItem.SECItemData)+' - '+inttostr(lenp));
   }

   {
   //using indy10 base64decode
   bytes:=Base64Decode (value,lenp);
   EncryptedSECItem.SECItemData :=pchar(@bytes[0]); //pchar(output);
   EncryptedSECItem.SECItemLen :=lenp; //(length(value) div 4 * 3) - 1;
   }

   //or using FPC base64
   output:=DecodeStringBase64(value);
   EncryptedSECItem.SECItemData :=pchar(@output[1]);
   EncryptedSECItem.SECItemLen :=length(output);
   //or
   //EncryptedSECItem.SECItemData:=allocmem(8192);
   //EncryptedSECItem.SECItemLen :=lenp; //8192;
   //copymemory(EncryptedSECItem.SECItemData,@bytes[0],lenp);
   if EncryptedSECItem.SECItemData=nil then writeln('EncryptedSECItem.SECItemData=nil');
   //writeln(strpas(EncryptedSECItem.SECItemData)+' - '+inttostr(EncryptedSECItem.SECItemLen));

   end;

if PK11SDR_Decrypt(@EncryptedSECItem, @DecryptedSECItem, nil) = 0 then
            begin
            decrypted := strpas(DecryptedSECItem.SECItemData);
            SetLength(decrypted, DecryptedSECItem.SECItemLen);
            end;
end;

procedure decrypt_sqlite(MainProfilePath:pchar);
const
SQLITE_ROW        = 100; //in sqlite3.pas
var
 value,res1,res2:string;
 //
  DB: TSQLite3Database;
  Stmt  : TSQLite3Statement;
begin
  DB := TSQLite3Database.Create;
  try
    DB.Open(MainProfilePath);
    Stmt := DB.Prepare('SELECT hostname,encryptedUsername,encryptedPassword,length(encryptedPassword) from moz_logins');
    try
      while Stmt.Step = SQLITE_ROW do
      begin
      value:=Stmt.ColumnText (1);
      decrypt(value,res1);
      value:=Stmt.ColumnText (2);
      decrypt(value,res2);
      writeln(Stmt.ColumnText (0)+';'+res1+';'+res2);
      end;
    finally
      Stmt.Free;
    end;
  finally
    DB.Free;
  end;
end;

procedure decrypt_json(MainProfilePath:pchar);
var
 value,res1,res2:string;
 //
  js,xs:TlkJSONobject;
  xl:TlkJSONlist ;
  ws: TlkJSONstring;
  s: String;
  i: Integer;
  sl:TStrings ;
begin
      sl:=TStringList.Create ;
      sl.LoadFromFile(MainProfilePath);
      s:=sl.Text ;
      sl.free;
      js := TlkJSON.ParseText(s) as TlkJSONobject;
      try
      if not assigned(js) then
        begin
        writeln('error: xs not assigned!');
        exit;
        end;//if not assigned(js) then
      xl := js.Field['logins'] as TlkJSONlist;
      writeln('logins count:'+inttostr(xl.Count));
      for i:=0 to xl.Count -1 do
        begin
        xs:=xl.Child [i] as TlkJSONobject;
        value:=xs.getString('encryptedUsername');
        decrypt(value,res1);
        value:=xs.getString('encryptedPassword');
        decrypt(value,res2);
        writeln(xs.getString('hostname')+';'+res1+';'+res2);
        end; //for
      except
      on e:exception do writeln(e.Message );
      end;
end;

procedure decrypt_txt(MainProfilePath:pchar);
var
 //
 CurrentEntry, Site, Name, Value, Passwords,configdir,res        : string;
 PasswordFileSize, BytesRead                 : dword;
 PasswordFile              : THandle;
 PasswordFileData       : pchar;
 EncryptedSECItem, DecryptedSECItem                          : TSECItem;
begin
try
      PasswordFile := CreateFile(MainProfilePath, GENERIC_READ, FILE_SHARE_READ, nil, OPEN_EXISTING, 0, 0);
      PasswordFileSize := GetFileSize(PasswordFile, nil);
      GetMem(PasswordFileData, PasswordFileSize);
      ReadFile(PasswordFile, PasswordFileData^, PasswordFileSize, BytesRead, nil);
      CloseHandle(PasswordFile);
      Passwords := PasswordFileData;
      FreeMem(PasswordFileData);
      Delete(Passwords, 1, Pos('.' + #13#10, Passwords) + 2);
        while Length(Passwords) <> 0 do
        begin
          CurrentEntry := Copy(Passwords, 1, Pos('.' + #13#10, Passwords) - 1);
          Delete(Passwords, 1, Length(CurrentEntry) + 3);
          Site := Copy(CurrentEntry, 1, Pos(#13#10, CurrentEntry) - 1);
          Delete(CurrentEntry, 1, Length(Site) + 2);
          while Length(CurrentEntry) <> 0 do
          begin
            Name := Copy(CurrentEntry, 1, Pos(#13#10, CurrentEntry) - 1);
            if Length(Name) = 0 then Name := '(unnamed value)';
            Delete(CurrentEntry, 1, Length(Name) + 2);
            Value := Copy(CurrentEntry, 1, Pos(#13#10, CurrentEntry) - 1);
            decrypt(value,res);
            Delete(CurrentEntry, 1, Length(Value) + 2);
          end; //while Length(CurrentEntry) <> 0 do
        writeln(site+';'+name+';'+res);
        end;//while Length(Passwords) <> 0 do
except
on e:exception do writeln(e.Message );
end;
end;

procedure GetFirefoxPasswords;


var
  NSSModule,glueLib, UserenvModule, hToken              : THandle;
  ProfilePath, MainProfile,isrelative                         : array [0..MAX_PATH] of char;
  ProfilePathLen                  : dword;
  FirefoxProfilePath, MainProfilePath       : pchar;
  ProgramPath:string;
  configdir        : string;
  KeySlot                                                     : pointer;
  //

begin
  //

  //

ProgramPath:=FolderPath(CSIDL_PROGRAM_FILES)+ '\Mozilla Firefox\';
if not FileExists (ProgramPath  + 'nss3.dll') then ProgramPath :=FolderPath(CSIDL_PROGRAM_FILES) +' (x86)\Mozilla Firefox\' ;
//ProgramPath:='e:\FirefoxPortable\App\Firefox\'; //WORKS X32
//ProgramPath:='E:\FirefoxPortable\App\Firefox64\'; //WORKS X64
writeln(ProgramPath);
  //LoadLibrary(pchar(ProgramPath  + 'mozcrt19.dll'));
  //LoadLibrary(pchar(ProgramPath  + 'sqlite3.dll'));
  //LoadLibrary(pchar(ProgramPath  + 'mozutils.dll')); //added
  glueLib:=0;
  glueLib:=LoadLibrary(pchar(ProgramPath + 'mozglue.dll')); //added //***
  if glueLib=0 then writeln('glueLib:='+inttostr(getlasterror));
  //LoadLibrary(pchar(ProgramPath + 'mozsqlite3.dll')); //added
  //LoadLibrary(pchar(ProgramPath + 'nspr4.dll'));
  //LoadLibrary(pchar(ProgramPath + 'plc4.dll'));
  //LoadLibrary(pchar(ProgramPath + 'plds4.dll'));
  //LoadLibrary(pchar(ProgramPath + 'nssutil3.dll'));
  //LoadLibrary(pchar(ProgramPath + 'softokn3.dll'));
  NSSModule:=0;
  NSSModule := LoadLibrary(pchar(ProgramPath + 'nss3.dll'));
  if NSSModule=0 then writeln('NSSModule:='+inttostr(getlasterror));
  //LoadLibrary(pchar(ProgramPath + 'softokn3.dll'));
  @NSS_Init:=nil;
  @NSS_Init := GetProcAddress(NSSModule, 'NSS_Init');
  if nativeuint(@NSS_Init )=0 then writeln('NSS_Init:='+inttostr(getlasterror));
  if @nss_init=nil then
    begin
    writeln('abort, modules missing');
    exit;
    end;
  @NSSBase64_DecodeBuffer:=nil;
  @NSSBase64_DecodeBuffer := GetProcAddress(NSSModule, 'NSSBase64_DecodeBuffer');
  if nativeuint(@NSSBase64_DecodeBuffer )=0 then
     begin
     writeln('NSSBase64_DecodeBuffer:='+inttostr(getlasterror));
     @ATOB_AsciiToData:=0;
     @ATOB_AsciiToData:= GetProcAddress(NSSModule, 'ATOB_AsciiToData');
     if nativeuint(@ATOB_AsciiToData )=0 then writeln('ATOB_AsciiToData:='+inttostr(getlasterror));
     end;
  //@PL_Base64Decode:= GetProcAddress(NSSModule, 'PL_Base64Decode');
  //if nativeuint(@PL_Base64Decode )=0 then writeln('PL_Base64Decode:='+inttostr(getlasterror));
  @PK11_GetInternalKeySlot := GetProcAddress(NSSModule, 'PK11_GetInternalKeySlot');
  @PK11_Authenticate:=0;
  @PK11_Authenticate := GetProcAddress(NSSModule, 'PK11_Authenticate');
  if nativeuint(@PK11_Authenticate )=0 then writeln('PK11_Authenticate:='+inttostr(getlasterror));
  @PK11SDR_Decrypt:=0;
  @PK11SDR_Decrypt := GetProcAddress(NSSModule, 'PK11SDR_Decrypt');
  if nativeuint(@PK11SDR_Decrypt )=0 then writeln('PK11SDR_Decrypt:='+inttostr(getlasterror));
  @NSS_Shutdown := GetProcAddress(NSSModule, 'NSS_Shutdown');
  @PK11_FreeSlot := GetProcAddress(NSSModule, 'PK11_FreeSlot');

  UserenvModule := LoadLibrary('userenv.dll');
  @GetUserProfileDirectory := GetProcAddress(UserenvModule, 'GetUserProfileDirectoryA');
  OpenProcessToken(GetCurrentProcess, TOKEN_QUERY, hToken);
  ProfilePathLen := MAX_PATH;
  ZeroMemory(@ProfilePath, MAX_PATH);
  GetUserProfileDirectory(hToken, @ProfilePath, ProfilePathLen);
  FirefoxProfilePath := pchar(FolderPath(CSIDL_APPDATA) + '\Mozilla\Firefox\'  + 'profiles.ini');
  GetPrivateProfileString('Profile0', 'Path', '', MainProfile, MAX_PATH, FirefoxProfilePath);
  GetPrivateProfileString('Profile0', 'isrelative', '', isrelative, MAX_PATH, FirefoxProfilePath);
  if strpas(isrelative)='0'
    then configdir:=MainProfile
    else configdir:=FolderPath(CSIDL_APPDATA) + '\Mozilla\Firefox\'  +  MainProfile;
  writeln(configdir);

//**************  signongs3.txt ****************************
  if strpas(isrelative)='0'
    then MainProfilePath :=pchar(MainProfile+ '\signons3.txt')
    else MainProfilePath := pchar(FolderPath(CSIDL_APPDATA) + '\Mozilla\Firefox\' + MainProfile  + '\signons3.txt');
if FileExists(MainProfilePath) then
 begin
  if NSS_Init(pchar(configdir)) = 0 then
  begin
    KeySlot := PK11_GetInternalKeySlot;
    if KeySlot <> nil then
    begin
      if PK11_Authenticate(KeySlot, True, nil) = 0 then
      begin
      decrypt_txt(MainProfilePath ); 
      end; //if PK11_Authenticate(KeySlot, True, nil) = 0 then
      PK11_FreeSlot(KeySlot);
    end; //if KeySlot <> nil then
    NSS_Shutdown;
  end; //if NSS_Init(pchar(configdir)) = 0 then
  exit;
  end; //if FileExists(MainProfilePath) then

  //************* JSON **********************************************
  if strpas(isrelative)='0'
  then MainProfilePath :=pchar(MainProfile+ '\logins.json')
  else MainProfilePath := pchar(FolderPath(CSIDL_APPDATA) + '\Mozilla\Firefox\' + MainProfile  + '\logins.json');
  if fileexists(MainProfilePath) then
  begin
  if NSS_Init(pchar(configdir)) = 0 then
  begin
    KeySlot := PK11_GetInternalKeySlot;
    if KeySlot <> nil then
    begin
      if PK11_Authenticate(KeySlot, True, nil) = 0 then
      //will fail is there is a master password
      //then use PK11_CheckUserPassword(keyslot, password)
      begin
      decrypt_json(MainProfilePath);
      end; //if PK11_Authenticate(KeySlot, True, nil) = 0 then
      PK11_FreeSlot(KeySlot);
    end; //if KeySlot <> nil then
    NSS_Shutdown;
  end;//if NSS_Init(pchar(configdir)) = 0 then
  exit;
  end;

  //*************  sqlite *******************************************
  if strpas(isrelative)='0'
  then MainProfilePath :=pchar(MainProfile+ '\signons.sqlite')
  else MainProfilePath := pchar(FolderPath(CSIDL_APPDATA) + '\Mozilla\Firefox\' + MainProfile  + '\signons.sqlite');
  if fileexists(MainProfilePath) then
  begin
  writeln('start 4');
  if NSS_Init(pchar(configdir)) = 0 then
  begin
    KeySlot := PK11_GetInternalKeySlot;
    if KeySlot <> nil then
    begin
      if PK11_Authenticate(KeySlot, True, nil) = 0 then
      begin
      decrypt_sqlite(MainProfilePath );
      end;//if PK11_Authenticate(KeySlot, True, nil)
  PK11_FreeSlot(KeySlot);
  end;//if KeySlot <> nil then
  NSS_Shutdown;
  end;//if NSS_Init(pchar(configdir)) = 0 then
  exit;
  end; //sqlite
//*******************************************************************

  end;

begin
WriteLn('Firefox Password Decrypter by Erwan2212@gmail.com');
GetFirefoxPasswords;
end.
