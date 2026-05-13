unit TestWebSearchTool;

interface

uses
  System.SysUtils, System.JSON, System.IOUtils,
  Settings.Config, Core.Messages, Core.AgentState, Tools.WebSearchTool,
  PiMonoTestFramework;

procedure RegisterWebSearchToolTests;

implementation

type
  TTestWebSearchTool = class
  public
    // Parameter validation (real tests)
    procedure Test_Search_EmptyQuery_Error;
    procedure Test_Search_MaxResults_ClampedLow;
    procedure Test_Search_MaxResults_ClampedHigh;
    procedure Test_Search_NoProvider_Error;
    procedure Test_Fetch_EmptyUrl_Error;
  end;

{ TTestWebSearchTool }

procedure TTestWebSearchTool.Test_Search_EmptyQuery_Error;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Cfg: TSearchConfig;
begin
  Cfg := Default(TSearchConfig);
  Cfg.Provider := spGoogle;
  Cfg.ApiKey := 'test';
  Tool := CreateWebSearchTool(Cfg, '');
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', '');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Empty query should return error');
      Assert(Pos('query', (R.Content[0] as TTextContent).Text) > 0, 'Error should mention query');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWebSearchTool.Test_Search_MaxResults_ClampedLow;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Cfg: TSearchConfig;
begin
  Cfg := Default(TSearchConfig);
  Cfg.Provider := spNone;
  Tool := CreateWebSearchTool(Cfg, '');
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', 'test');
    Params.AddPair('max_results', TJSONNumber.Create(-5));
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should return error for spNone provider');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWebSearchTool.Test_Search_MaxResults_ClampedHigh;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Cfg: TSearchConfig;
begin
  Cfg := Default(TSearchConfig);
  Cfg.Provider := spNone;
  Tool := CreateWebSearchTool(Cfg, '');
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', 'test');
    Params.AddPair('max_results', TJSONNumber.Create(100));
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Should return error for spNone provider');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWebSearchTool.Test_Search_NoProvider_Error;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Cfg: TSearchConfig;
begin
  Cfg := Default(TSearchConfig);
  Cfg.Provider := spNone;
  Tool := CreateWebSearchTool(Cfg, '');
  if Tool = nil then
  begin
    Assert(True, 'No provider returns nil tool');
    Exit;
  end;
  Params := TJSONObject.Create;
  try
    Params.AddPair('query', 'test');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'No provider should return error');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

procedure TTestWebSearchTool.Test_Fetch_EmptyUrl_Error;
var
  Tool: IAgentTool;
  Params: TJSONObject;
  R: TToolResult;
  Cfg: TSearchConfig;
begin
  Cfg := Default(TSearchConfig);
  Tool := CreateWebFetchTool(Cfg, '');
  Params := TJSONObject.Create;
  try
    Params.AddPair('url', '');
    R := Tool.Execute('tc1', Params, function: Boolean begin Result := False; end);
    try
      Assert(R.IsError, 'Empty URL should return error');
      Assert(Pos('url', (R.Content[0] as TTextContent).Text) > 0, 'Error should mention url');
    finally
      R.ReleaseContent;
    end;
  finally
    Params.Free;
  end;
end;

{ Registration }

procedure RegisterWebSearchToolTests;
var
  T: TTestWebSearchTool;
begin
  T := TTestWebSearchTool.Create;
  try
    GRunner.RunTest('WebSearch: Empty query error', T.Test_Search_EmptyQuery_Error);
    GRunner.RunTest('WebSearch: No provider rejects negative limit', T.Test_Search_MaxResults_ClampedLow);
    GRunner.RunTest('WebSearch: No provider rejects high limit', T.Test_Search_MaxResults_ClampedHigh);
    GRunner.RunTest('WebSearch: No provider error', T.Test_Search_NoProvider_Error);
    GRunner.RunTest('WebFetch: Empty URL error', T.Test_Fetch_EmptyUrl_Error);
  finally
    T.Free;
  end;
end;

end.
