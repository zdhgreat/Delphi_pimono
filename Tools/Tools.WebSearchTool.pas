unit Tools.WebSearchTool;

interface

uses
  System.SysUtils, System.Classes, System.JSON, System.Net.HttpClient,
  System.Net.URLClient, System.NetConsts, System.NetEncoding, System.RegularExpressions,
  System.Generics.Collections, System.Math,
  Core.Messages, Core.AgentState, Tools.ITool, Settings.Config,
  Utils.JsonHelper;

type
  TSearchResult = record
    Title: string;
    URL: string;
    Snippet: string;
  end;

  TWebSearchTool = class(TBaseTool)
  private
    FProvider: TSearchProvider;
    FApiKey: string;
    FCustomId: string;
    FMaxResults: Integer;
    FTimeout: Integer;
    function SearchGoogle(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchDuckDuckGo(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchSearXNG(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchBrave(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchSerper(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchTavily(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchYouCom(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchExa(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchFirecrawl(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchLinkup(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function SearchPerplexity(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
    function FormatResults(const AQuery: string; const AResults: TArray<TSearchResult>): string;
    function DoHttpGet(const AUrl: string; const AHeaders: TArray<TPair<string, string>>; out AResponse: string): Boolean;
    function DoHttpPost(const AUrl: string; const ABody: TJSONObject; const AHeaders: TArray<TPair<string, string>>; out AResponse: string): Boolean;
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

  TWebFetchTool = class(TBaseTool)
  private
    FFetchMaxLength: Integer;
    FTimeout: Integer;
    function StripHtml(const AHtml: string): string;
  protected
    function GetName: string; override;
    function GetLabel: string; override;
    function GetDescription: string; override;
    function GetParameterSchema: TJSONObject; override;
  public
    constructor Create(const AWorkingDir: string); override;
    function Execute(const AToolCallId: string; AParams: TJSONObject;
      AIsAborted: TAbortedCallback): TToolResult; override;
  end;

function CreateWebSearchTool(const AConfig: TSearchConfig; const AWorkingDir: string): IAgentTool;
function CreateWebFetchTool(const AConfig: TSearchConfig; const AWorkingDir: string): IAgentTool;

implementation

{ SSRF Protection: Block requests to private/internal/metadata IPs and hostnames }

function IsBlockedUrl(const AUrl: string): Boolean;
var
  URI: TURI;
  Host: string;

  function MatchesPrivateIP(const AHost: string): Boolean;
  var
    Parts: TArray<string>;
    Octet: Integer;
  begin
    Result := False;
    // 127.x.x.x - loopback
    if AHost.StartsWith('127.') then Exit(True);
    // 10.x.x.x - private class A
    if AHost.StartsWith('10.') then Exit(True);
    // 192.168.x.x - private class C
    if AHost.StartsWith('192.168.') then Exit(True);
    // 169.254.x.x - link-local / metadata endpoint
    if AHost.StartsWith('169.254.') then Exit(True);
    // 0.x.x.x - current network
    if AHost.StartsWith('0.') then Exit(True);

    // 172.16.x.x - 172.31.x.x - private class B
    if AHost.StartsWith('172.') then
    begin
      Parts := AHost.Split(['.']);
      if Length(Parts) >= 2 then
      begin
        if TryStrToInt(Parts[1], Octet) then
          if (Octet >= 16) and (Octet <= 31) then
            Exit(True);
      end;
    end;
  end;

begin
  Result := False;
  try
    URI := TURI.Create(AUrl);
    Host := URI.Host.ToLowerInvariant;
  except
    // If URL cannot be parsed, block it
    Exit(True);
  end;

  // Block common internal hostnames
  if (Host = 'localhost') or (Host = 'localhost.localdomain') then
    Exit(True);

  // Block IPv6 loopback
  if (Host = '::1') or (Host = '[::1]') or (Host = '0:0:0:0:0:0:0:1') then
    Exit(True);

  // Block metadata endpoints (cloud provider metadata)
  if (Host = 'metadata.google.internal') or
     (Host = 'metadata.azure.com') or
     (Host = '169.254.169.254') then
    Exit(True);

  // Block host-based private IP checks
  if MatchesPrivateIP(Host) then
    Exit(True);

  // Block URLs with credentials (user:pass@host)
  // Check the URL string between "://" and the next "/" for "@"
  var SchemeEnd := Pos('://', AUrl);
  if SchemeEnd > 0 then
  begin
    var AuthPart := Copy(AUrl, SchemeEnd + 3, MaxInt);
    var SlashPos := Pos('/', AuthPart);
    if SlashPos > 0 then
      AuthPart := Copy(AuthPart, 1, SlashPos - 1);
    if Pos('@', AuthPart) > 0 then
      Exit(True);
  end;
end;

{ TWebSearchTool }

constructor TWebSearchTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
  FProvider := spNone;
  FApiKey := '';
  FCustomId := '';
  FMaxResults := 5;
  FTimeout := 15000;
end;

function TWebSearchTool.GetName: string;
begin
  Result := 'web_search';
end;

function TWebSearchTool.GetLabel: string;
begin
  Result := 'Web Search';
end;

function TWebSearchTool.GetDescription: string;
begin
  Result := 'Search the internet for up-to-date information. Returns a list of search results with titles, URLs, and snippets.';
end;

function TWebSearchTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('query', BuildStringParam('query', 'The search query'));
  Props.AddPair('max_results', BuildIntegerParam('max_results', 'Maximum number of results to return (1-10, default 5)'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('query');
  Result.AddPair('required', Req);
end;

function TWebSearchTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Query: string;
  MaxResults: Integer;
  Results: TArray<TSearchResult>;
  Text: string;
  List: TContentBlockList;
begin
  Query := JsonGetStr(AParams, 'query', '');
  MaxResults := JsonGetInt(AParams, 'max_results', FMaxResults);
  if MaxResults < 1 then MaxResults := 1;
  if MaxResults > 10 then MaxResults := 10;

  if Query = '' then
    Exit(TToolResult.CreateError('query parameter is required'));

  try
    case FProvider of
      spGoogle:      Results := SearchGoogle(Query, MaxResults);
      spDuckDuckGo:  Results := SearchDuckDuckGo(Query, MaxResults);
      spSearXNG:     Results := SearchSearXNG(Query, MaxResults);
      spBrave:       Results := SearchBrave(Query, MaxResults);
      spSerper:      Results := SearchSerper(Query, MaxResults);
      spTavily:      Results := SearchTavily(Query, MaxResults);
      spYouCom:      Results := SearchYouCom(Query, MaxResults);
      spExa:         Results := SearchExa(Query, MaxResults);
      spFirecrawl:   Results := SearchFirecrawl(Query, MaxResults);
      spLinkup:      Results := SearchLinkup(Query, MaxResults);
      spPerplexity:  Results := SearchPerplexity(Query, MaxResults);
    else
      Exit(TToolResult.CreateError('No search provider configured'));
    end;

    Text := FormatResults(Query, Results);
    List := TContentBlockList.Create;
    List.Add(TTextContent.Create(Text));
    Result := TToolResult.Create(List, False);
  except
    on E: Exception do
      Result := TToolResult.CreateError('Search failed: ' + E.Message);
  end;
end;

{ HTTP Helpers }

function TWebSearchTool.DoHttpGet(const AUrl: string;
  const AHeaders: TArray<TPair<string, string>>; out AResponse: string): Boolean;
var
  Client: THTTPClient;
  Response: IHTTPResponse;
  i: Integer;
begin
  if IsBlockedUrl(AUrl) then
    raise Exception.Create('Blocked: URL targets a private or internal address (SSRF protection)');
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := FTimeout;
    Client.ResponseTimeout := FTimeout;
    for i := 0 to High(AHeaders) do
      Client.CustomHeaders[AHeaders[i].Key] := AHeaders[i].Value;
    Response := Client.Get(AUrl);
    AResponse := Response.ContentAsString(TEncoding.UTF8);
    Result := Response.StatusCode = 200;
    if not Result then
      AResponse := Format('HTTP %d: %s', [Response.StatusCode, Copy(AResponse, 1, 500)]);
  finally
    Client.Free;
  end;
end;

function TWebSearchTool.DoHttpPost(const AUrl: string; const ABody: TJSONObject;
  const AHeaders: TArray<TPair<string, string>>; out AResponse: string): Boolean;
var
  Client: THTTPClient;
  BodyStream: TStringStream;
  Response: IHTTPResponse;
  i: Integer;
begin
  if IsBlockedUrl(AUrl) then
    raise Exception.Create('Blocked: URL targets a private or internal address (SSRF protection)');
  Client := THTTPClient.Create;
  try
    Client.ConnectionTimeout := FTimeout;
    Client.ResponseTimeout := FTimeout;
    Client.ContentType := 'application/json';
    for i := 0 to High(AHeaders) do
      Client.CustomHeaders[AHeaders[i].Key] := AHeaders[i].Value;
    BodyStream := TStringStream.Create(ABody.ToJSON, TEncoding.UTF8);
    try
      Response := Client.Post(AUrl, BodyStream);
      AResponse := Response.ContentAsString(TEncoding.UTF8);
      Result := Response.StatusCode = 200;
      if not Result then
        AResponse := Format('HTTP %d: %s', [Response.StatusCode, Copy(AResponse, 1, 500)]);
    finally
      BodyStream.Free;
    end;
  finally
    Client.Free;
  end;
end;

{ Google Custom Search }

function TWebSearchTool.SearchGoogle(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Url, Response: string;
  Json, Item: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Url := Format('https://www.googleapis.com/customsearch/v1?key=%s&cx=%s&q=%s&num=%d',
    [FApiKey, FCustomId, TNetEncoding.URL.Encode(AQuery), AMax]);

  if not DoHttpGet(Url, nil, Response) then
    raise Exception.Create('Google Search API error: ' + Response);

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Google Search response');

  try
    Items := Json.GetValue('items') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'link', '');
      Result[i].Snippet := JsonGetStr(Item, 'snippet', '');
    end;
  finally
    Json.Free;
  end;
end;

{ DuckDuckGo HTML Search }

function TWebSearchTool.SearchDuckDuckGo(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Url, Response: string;
  TitleMatch, SnippetMatch: TMatch;
  Pattern: string;
  i: Integer;
  Titles, Urls, Snippets: TArray<string>;
begin
  Result := nil;
  Url := 'https://html.duckduckgo.com/html/?q=' + TNetEncoding.URL.Encode(AQuery);

  if not DoHttpGet(Url, nil, Response) then
    raise Exception.Create('DuckDuckGo search error: ' + Response);

  // Parse HTML results
  Pattern := '<a rel="nofollow" class="result__a" href="([^"]+)".*?>(.*?)</a>';
  TitleMatch := TRegEx.Match(Response, Pattern, [roSingleLine, roIgnoreCase]);

  SetLength(Titles, 0);
  SetLength(Urls, 0);
  SetLength(Snippets, 0);

  while TitleMatch.Success do
  begin
    SetLength(Urls, Length(Urls) + 1);
    Urls[High(Urls)] := TitleMatch.Groups[1].Value;

    SetLength(Titles, Length(Titles) + 1);
    Titles[High(Titles)] := TRegEx.Replace(TitleMatch.Groups[2].Value, '<[^>]+>', '');

    TitleMatch := TitleMatch.NextMatch;
  end;

  // Parse snippets
  Pattern := '<a class="result__snippet".*?>(.*?)</a>';
  SnippetMatch := TRegEx.Match(Response, Pattern, [roSingleLine, roIgnoreCase]);
  while SnippetMatch.Success do
  begin
    SetLength(Snippets, Length(Snippets) + 1);
    Snippets[High(Snippets)] := TRegEx.Replace(SnippetMatch.Groups[1].Value, '<[^>]+>', '');
    SnippetMatch := SnippetMatch.NextMatch;
  end;

  // Build results
  SetLength(Result, Min(Min(Length(Titles), Length(Urls)), AMax));
  for i := 0 to High(Result) do
  begin
    Result[i].Title := Titles[i];
    Result[i].URL := Urls[i];
    if i < Length(Snippets) then
      Result[i].Snippet := Snippets[i]
    else
      Result[i].Snippet := '';
  end;
end;

{ SearXNG }

function TWebSearchTool.SearchSearXNG(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Url, Response: string;
  Json, Item: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  if FCustomId = '' then
    raise Exception.Create('SearXNG instance URL is required (set in CustomId field)');
  Url := IncludeTrailingPathDelimiter(FCustomId) +
    Format('search?q=%s&format=json', [TNetEncoding.URL.Encode(AQuery)]);

  if not DoHttpGet(Url, nil, Response) then
    raise Exception.Create('SearXNG search error: ' + Response);

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid SearXNG response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      Result[i].Snippet := JsonGetStr(Item, 'content', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Brave Search }

function TWebSearchTool.SearchBrave(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Url, Response: string;
  Json, Item: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Url := Format('https://api.search.brave.com/res/v1/web/search?q=%s&count=%d',
    [TNetEncoding.URL.Encode(AQuery), AMax]);

  if not DoHttpGet(Url,
    [TPair<string, string>.Create('X-Subscription-Token', FApiKey),
     TPair<string, string>.Create('Accept', 'application/json')],
    Response) then
    raise Exception.Create('Brave Search error: ' + Response);

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Brave Search response');

  try
    var WebObj := Json.GetValue('web') as TJSONObject;
    if WebObj = nil then Exit;
    Items := WebObj.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      Result[i].Snippet := JsonGetStr(Item, 'description', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Serper.dev }

function TWebSearchTool.SearchSerper(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('q', AQuery);
    Body.AddPair('num', TJSONNumber.Create(AMax));

    if not DoHttpPost('https://google.serper.dev/search', Body,
      [TPair<string, string>.Create('X-API-KEY', FApiKey)],
      Response) then
      raise Exception.Create('Serper error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Serper response');

  try
    Items := Json.GetValue('organic') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'link', '');
      Result[i].Snippet := JsonGetStr(Item, 'snippet', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Tavily }

function TWebSearchTool.SearchTavily(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', AQuery);
    Body.AddPair('api_key', FApiKey);
    Body.AddPair('max_results', TJSONNumber.Create(AMax));

    if not DoHttpPost('https://api.tavily.com/search', Body, nil, Response) then
      raise Exception.Create('Tavily error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Tavily response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      Result[i].Snippet := JsonGetStr(Item, 'content', '');
    end;
  finally
    Json.Free;
  end;
end;

{ You.com }

function TWebSearchTool.SearchYouCom(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Url, Response: string;
  Json, Item: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Url := Format('https://api.ydc-index.io/search?q=%s&num_web_results=%d',
    [TNetEncoding.URL.Encode(AQuery), AMax]);

  if not DoHttpGet(Url,
    [TPair<string, string>.Create('X-API-Key', FApiKey)],
    Response) then
    raise Exception.Create('You.com search error: ' + Response);

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid You.com response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      Result[i].Snippet := JsonGetStr(Item, 'description', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Exa }

function TWebSearchTool.SearchExa(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', AQuery);
    Body.AddPair('numResults', TJSONNumber.Create(AMax));
    Body.AddPair('type', 'auto');
    Body.AddPair('contents', TJSONObject.ParseJSONValue('{"text": {"maxCharacters": 200}}') as TJSONObject);

    if not DoHttpPost('https://api.exa.ai/search', Body,
      [TPair<string, string>.Create('x-api-key', FApiKey)],
      Response) then
      raise Exception.Create('Exa error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Exa response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      // Exa returns text in contents.text
      var Contents := Item.GetValue('text') as TJSONObject;
      if Contents <> nil then
        Result[i].Snippet := JsonGetStr(Contents, 'text', '')
      else
        Result[i].Snippet := '';
    end;
  finally
    Json.Free;
  end;
end;

{ Firecrawl }

function TWebSearchTool.SearchFirecrawl(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', AQuery);
    Body.AddPair('limit', TJSONNumber.Create(AMax));

    if not DoHttpPost('https://api.firecrawl.dev/v0/search', Body,
      [TPair<string, string>.Create('Authorization', 'Bearer ' + FApiKey)],
      Response) then
      raise Exception.Create('Firecrawl error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Firecrawl response');

  try
    Items := Json.GetValue('data') as TJSONArray;
    if Items = nil then
      Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      // Prefer 'url', fall back to 'link' if url is empty
      Result[i].URL := JsonGetStr(Item, 'url', '');
      if Result[i].URL = '' then
        Result[i].URL := JsonGetStr(Item, 'link', '');
      Result[i].Snippet := JsonGetStr(Item, 'description', '');
      if Result[i].Snippet = '' then
        Result[i].Snippet := JsonGetStr(Item, 'snippet', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Linkup }

function TWebSearchTool.SearchLinkup(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', AQuery);
    Body.AddPair('outputType', 'searchResults');
    Body.AddPair('includeImages', TJSONBool.Create(False));

    if not DoHttpPost('https://api.linkup.so/v1/search', Body,
      [TPair<string, string>.Create('Authorization', 'Bearer ' + FApiKey)],
      Response) then
      raise Exception.Create('Linkup error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Linkup response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      Item := Items.Items[i] as TJSONObject;
      Result[i].Title := JsonGetStr(Item, 'title', '');
      Result[i].URL := JsonGetStr(Item, 'url', '');
      Result[i].Snippet := JsonGetStr(Item, 'content', '');
      if Result[i].Snippet = '' then
        Result[i].Snippet := JsonGetStr(Item, 'snippet', '');
    end;
  finally
    Json.Free;
  end;
end;

{ Perplexity }

function TWebSearchTool.SearchPerplexity(const AQuery: string; AMax: Integer): TArray<TSearchResult>;
var
  Response: string;
  Json, Item: TJSONObject;
  Body: TJSONObject;
  Items: TJSONArray;
  i, Count: Integer;
begin
  Result := nil;
  Body := TJSONObject.Create;
  try
    Body.AddPair('query', AQuery);
    Body.AddPair('num_results', TJSONNumber.Create(AMax));

    if not DoHttpPost('https://api.perplexity.ai/search', Body,
      [TPair<string, string>.Create('Authorization', 'Bearer ' + FApiKey)],
      Response) then
      raise Exception.Create('Perplexity error: ' + Response);
  finally
    Body.Free;
  end;

  Json := TJSONObject.ParseJSONValue(Response) as TJSONObject;
  if Json = nil then
    raise Exception.Create('Invalid Perplexity response');

  try
    Items := Json.GetValue('results') as TJSONArray;
    if Items = nil then
      Items := Json.GetValue('citations') as TJSONArray;
    if Items = nil then Exit;

    Count := Min(Items.Count, AMax);
    SetLength(Result, Count);
    for i := 0 to Count - 1 do
    begin
      if Items.Items[i] is TJSONObject then
      begin
        Item := Items.Items[i] as TJSONObject;
        Result[i].Title := JsonGetStr(Item, 'title', '');
        // Prefer 'url', fall back to 'link' if url is empty
        Result[i].URL := JsonGetStr(Item, 'url', '');
        if Result[i].URL = '' then
          Result[i].URL := JsonGetStr(Item, 'link', '');
        Result[i].Snippet := JsonGetStr(Item, 'text', '');
        if Result[i].Snippet = '' then
          Result[i].Snippet := JsonGetStr(Item, 'snippet', '');
      end
      else if Items.Items[i] is TJSONString then
      begin
        // Perplexity may return citation URLs as strings
        Result[i].Title := '';
        Result[i].URL := (Items.Items[i] as TJSONString).Value;
        Result[i].Snippet := '';
      end;
    end;
  finally
    Json.Free;
  end;
end;

{ Format Results }

function TWebSearchTool.FormatResults(const AQuery: string;
  const AResults: TArray<TSearchResult>): string;
var
  SB: TStringBuilder;
  i: Integer;
begin
  SB := TStringBuilder.Create;
  try
    SB.AppendLine(Format('[Web Search: "%s"]', [AQuery]));
    if Length(AResults) = 0 then
    begin
      SB.AppendLine('No results found.');
      Exit(SB.ToString);
    end;

    for i := 0 to High(AResults) do
    begin
      SB.AppendLine(Format('Result %d:', [i + 1]));
      SB.AppendLine('  Title: ' + AResults[i].Title);
      SB.AppendLine('  URL: ' + AResults[i].URL);
      if AResults[i].Snippet <> '' then
        SB.AppendLine('  Snippet: ' + AResults[i].Snippet);
    end;
    SB.AppendLine(Format('[Found %d results]', [Length(AResults)]));
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

{ TWebFetchTool }

constructor TWebFetchTool.Create(const AWorkingDir: string);
begin
  inherited Create(AWorkingDir);
  FFetchMaxLength := 5000;
  FTimeout := 15000;
end;

function TWebFetchTool.GetName: string;
begin
  Result := 'web_fetch';
end;

function TWebFetchTool.GetLabel: string;
begin
  Result := 'Fetch Web Page';
end;

function TWebFetchTool.GetDescription: string;
begin
  Result := 'Fetch and extract text content from a web page URL. Returns the page text without HTML tags.';
end;

function TWebFetchTool.GetParameterSchema: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('type', 'object');
  var Props := TJSONObject.Create;
  Props.AddPair('url', BuildStringParam('url', 'The URL of the web page to fetch'));
  Props.AddPair('max_length', BuildIntegerParam('max_length', 'Maximum characters to return (default 5000)'));
  Result.AddPair('properties', Props);
  var Req := TJSONArray.Create;
  Req.Add('url');
  Result.AddPair('required', Req);
end;

function TWebFetchTool.StripHtml(const AHtml: string): string;
var
  Text: string;
begin
  // Remove script and style blocks
  Text := TRegEx.Replace(AHtml, '<script[^>]*>.*?</script>', '', [roSingleLine, roIgnoreCase]);
  Text := TRegEx.Replace(Text, '<style[^>]*>.*?</style>', '', [roSingleLine, roIgnoreCase]);
  // Replace block tags with newlines
  Text := TRegEx.Replace(Text, '<(br|p|div|li|h[1-6]|tr)[^>]*>', #10, [roIgnoreCase]);
  // Remove all remaining HTML tags
  Text := TRegEx.Replace(Text, '<[^>]+>', '');
  // Decode common HTML entities
  Text := StringReplace(Text, '&amp;', '&', [rfReplaceAll]);
  Text := StringReplace(Text, '&lt;', '<', [rfReplaceAll]);
  Text := StringReplace(Text, '&gt;', '>', [rfReplaceAll]);
  Text := StringReplace(Text, '&quot;', '"', [rfReplaceAll]);
  Text := StringReplace(Text, '&#39;', '''', [rfReplaceAll]);
  Text := StringReplace(Text, '&nbsp;', ' ', [rfReplaceAll]);
  // Collapse whitespace
  Text := TRegEx.Replace(Text, '[ \t]+', ' ');
  Text := TRegEx.Replace(Text, #10' +', #10);
  Text := Text.Trim;
  Result := Text;
end;

function TWebFetchTool.Execute(const AToolCallId: string;
  AParams: TJSONObject; AIsAborted: TAbortedCallback): TToolResult;
var
  Url, Response, Text: string;
  Client: THTTPClient;
  Resp: IHTTPResponse;
  MaxLen: Integer;
  List: TContentBlockList;
begin
  Url := JsonGetStr(AParams, 'url', '');
  MaxLen := JsonGetInt(AParams, 'max_length', FFetchMaxLength);
  if MaxLen < 500 then MaxLen := 500;

  if Url = '' then
    Exit(TToolResult.CreateError('url parameter is required'));

  if IsBlockedUrl(Url) then
    Exit(TToolResult.CreateError('Blocked: URL targets a private or internal address (SSRF protection)'));

  try
    Client := THTTPClient.Create;
    try
      Client.ConnectionTimeout := FTimeout;
      Client.ResponseTimeout := FTimeout;
      Client.UserAgent := 'Mozilla/5.0 (compatible; PiMono/1.0)';
      Resp := Client.Get(Url);

      if Resp.StatusCode <> 200 then
        Exit(TToolResult.CreateError(Format('HTTP %d fetching %s', [Resp.StatusCode, Url])));

      Response := Resp.ContentAsString(TEncoding.UTF8);
      Text := StripHtml(Response);

      if Length(Text) > MaxLen then
        Text := Copy(Text, 1, MaxLen) + #10'... [content truncated]';

      List := TContentBlockList.Create;
      List.Add(TTextContent.Create(Format('[Fetched: %s]'#10#10'%s', [Url, Text])));
      Result := TToolResult.Create(List, False);
    finally
      Client.Free;
    end;
  except
    on E: Exception do
      Result := TToolResult.CreateError('Fetch failed: ' + E.Message);
  end;
end;

{ Factory functions }

function CreateWebSearchTool(const AConfig: TSearchConfig; const AWorkingDir: string): IAgentTool;
var
  Tool: TWebSearchTool;
begin
  // Moonshot uses built-in $web_search via tool_calls passthrough, not a local search tool
  if AConfig.Provider = spMoonshot then
    Exit(nil);

  Tool := TWebSearchTool.Create(AWorkingDir);
  Tool.FProvider := AConfig.Provider;
  Tool.FApiKey := AConfig.ApiKey;
  Tool.FCustomId := AConfig.CustomId;
  Tool.FMaxResults := AConfig.MaxResults;
  Tool.FTimeout := AConfig.Timeout;
  Result := Tool;
end;

function CreateWebFetchTool(const AConfig: TSearchConfig; const AWorkingDir: string): IAgentTool;
var
  Tool: TWebFetchTool;
begin
  Tool := TWebFetchTool.Create(AWorkingDir);
  Tool.FFetchMaxLength := AConfig.FetchMaxLength;
  Tool.FTimeout := AConfig.Timeout;
  Result := Tool;
end;

end.
