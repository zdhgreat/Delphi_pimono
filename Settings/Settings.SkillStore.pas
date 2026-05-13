unit Settings.SkillStore;

{ Directory-based skill storage following Agent Skills standard.
  Each skill is a directory under %APPDATA%\PiMono\skills\<id>\
  Structure:
    <id>\
      SKILL.md          — Main prompt with YAML frontmatter
      references\       — Optional reference documents (*.md)
      examples\         — Optional example documents (*.md)
}

interface

uses
  System.SysUtils, System.IOUtils, System.Classes,
  Settings.Config;

function GetSkillDir: string;
function LoadSkillPool: TArray<TSkillDef>;
procedure SaveSkill(const ASkill: TSkillDef);
procedure DeleteSkill(const ASkillId: string);
procedure SeedDefaults;
function SkillDirPath(const ASkillId: string): string;
function SkillFilePath(const ASkillId: string): string;
function ReadSubDirDocs(const ABaseDir, ASubDir: string): string;
function ParseFrontmatter(const AContent: string;
  out AId, ADisplayName, ADescription: string; out ABody: string): Boolean;
function InstallSkillFromPath(const AFilePath: string): TSkillDef;

implementation

{ Validates that a skill ID contains only safe characters and no traversal patterns.
  Allowed: alphanumeric (A-Z, a-z, 0-9), dash (-), underscore (_).
  Rejects: path separators, parent-directory sequences, null bytes, and control chars. }

procedure ValidateSkillId(const ASkillId: string);
var
  i: Integer;
begin
  if ASkillId = '' then
    raise Exception.Create('Invalid skill ID: must not be empty');

  if (Pos('..', ASkillId) > 0) or (Pos('\', ASkillId) > 0) or (Pos('/', ASkillId) > 0) then
    raise Exception.Create('Invalid skill ID: path traversal characters not allowed');

  for i := 1 to Length(ASkillId) do
  begin
    if not (CharInSet(ASkillId[i], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) ) then
      raise Exception.Create('Invalid skill ID: contains disallowed character "' + ASkillId[i] + '"');
  end;
end;

function GetSkillDir: string;
begin
  Result := IncludeTrailingPathDelimiter(
    GetEnvironmentVariable('APPDATA')) + 'PiMono\skills\';
end;

function SkillDirPath(const ASkillId: string): string;
begin
  ValidateSkillId(ASkillId);
  Result := GetSkillDir + ASkillId + '\';
end;

function SkillFilePath(const ASkillId: string): string;
begin
  ValidateSkillId(ASkillId);
  Result := SkillDirPath(ASkillId) + 'SKILL.md';
end;

{ --- YAML Frontmatter Parsing --- }

function ParseFrontmatter(const AContent: string;
  out AId, ADisplayName, ADescription: string; out ABody: string): Boolean;
var
  Lines: TArray<string>;
  i, BodyStart: Integer;
  Key, Val: string;
  Sep: Integer;
begin
  Result := False;
  AId := '';
  ADisplayName := '';
  ADescription := '';
  ABody := '';
  Lines := AContent.Split([#10, #13#10]);
  if (Length(Lines) = 0) or (Lines[0].Trim <> '---') then
    Exit;

  BodyStart := -1;
  for i := 1 to High(Lines) do
  begin
    if Lines[i].Trim = '---' then
    begin
      BodyStart := i + 1;
      Break;
    end;

    Sep := Pos(':', Lines[i]);
    if Sep > 0 then
    begin
      Key := Copy(Lines[i], 1, Sep - 1).Trim.ToLower;
      Val := Copy(Lines[i], Sep + 1, MaxInt).Trim;
      if Key = 'id' then AId := Val
      else if Key = 'displayname' then ADisplayName := Val
      else if Key = 'description' then ADescription := Val;
    end;
  end;

  if BodyStart < 0 then
    BodyStart := 1;

  // Reconstruct body
  for i := BodyStart to High(Lines) do
  begin
    if ABody <> '' then
      ABody := ABody + #10;
    ABody := ABody + Lines[i];
  end;

  // Trim leading blank lines from body
  while (Length(ABody) >= 1) and ((ABody[1] = #10) or (ABody[1] = #13)) do
      Delete(ABody, 1, 1);
  ABody := ABody.TrimRight;

  Result := (AId <> '');
end;

{ --- Helper: Read all .md files in a subdirectory and concatenate --- }

function ReadSubDirDocs(const ABaseDir, ASubDir: string): string;
var
  Dir, Content: string;
  Files: TArray<string>;
  i: Integer;
begin
  Result := '';
  Dir := IncludeTrailingPathDelimiter(ABaseDir) + ASubDir;
  if not DirectoryExists(Dir) then
    Exit;

  Files := TDirectory.GetFiles(Dir, '*.md');
  for i := 0 to High(Files) do
  begin
    try
      Content := TFile.ReadAllText(Files[i], TEncoding.UTF8).Trim;
      if Content <> '' then
      begin
        if Result <> '' then
          Result := Result + #10#10;
        // Add file-name header for context
        Result := Result + '--- ' +
          ChangeFileExt(ExtractFileName(Files[i]), '') + ' ---' + #10 +
          Content;
      end;
    except
      // Skip invalid files
    end;
  end;
end;

{ --- Install skill from a SKILL.md file path --- }

function InstallSkillFromPath(const AFilePath: string): TSkillDef;
var
  Content, Id, DisplayName, Description, Body, Dir: string;
begin
  Content := TFile.ReadAllText(AFilePath, TEncoding.UTF8);
  if not ParseFrontmatter(Content, Id, DisplayName, Description, Body) then
    raise Exception.Create('Invalid skill file: missing YAML frontmatter or id field.');

  Dir := ExtractFileDir(AFilePath);
  Result := TSkillDef.Create(Id, DisplayName, Description, Body,
    ReadSubDirDocs(Dir, 'references'),
    ReadSubDirDocs(Dir, 'examples'));
end;

{ --- Build SKILL.md content --- }

function BuildSkillMd(const ASkill: TSkillDef): string;
begin
  Result := '---' + #10 +
    'id: ' + ASkill.Id + #10 +
    'displayName: ' + ASkill.DisplayName + #10 +
    'description: ' + ASkill.Description + #10 +
    '---' + #10 +
    ASkill.Content;
end;

{ --- Write docs to a subdirectory (each paragraph separated by blank line -> one .md) --- }

procedure WriteSubDirDocs(const ABaseDir, ASubDir, AContent: string);
var
  Dir: string;
begin
  Dir := IncludeTrailingPathDelimiter(ABaseDir) + ASubDir;

  // Clear existing content
  if DirectoryExists(Dir) then
    TDirectory.Delete(Dir, True);

  if AContent.Trim = '' then
    Exit;

  ForceDirectories(Dir);

  // Write all content as a single _all.md file
  // (The content is already structured with --- filename --- headers from ReadSubDirDocs)
  TFile.WriteAllText(IncludeTrailingPathDelimiter(Dir) + '_all.md',
    AContent, TEncoding.UTF8);
end;

{ --- Public API --- }

function LoadSkillPool: TArray<TSkillDef>;
var
  BaseDir: string;
  Dirs: TArray<string>;
  i, Count: Integer;
  Content, Id, DisplayName, Description, Body: string;
  DirName: string;
begin
  Result := nil;
  BaseDir := GetSkillDir;
  if not DirectoryExists(BaseDir) then
    Exit;

  Dirs := TDirectory.GetDirectories(BaseDir);
  SetLength(Result, Length(Dirs));
  Count := 0;

  for i := 0 to High(Dirs) do
  begin
    DirName := ExtractFileName(Dirs[i]);
    // Look for SKILL.md inside the directory
    if not FileExists(SkillFilePath(DirName)) then
      Continue;

    try
      Content := TFile.ReadAllText(SkillFilePath(DirName), TEncoding.UTF8);
      if ParseFrontmatter(Content, Id, DisplayName, Description, Body) then
      begin
        Result[Count] := TSkillDef.Create(Id, DisplayName, Description, Body,
          ReadSubDirDocs(Dirs[i], 'references'),
          ReadSubDirDocs(Dirs[i], 'examples'));
        Inc(Count);
      end;
    except
      // Skip invalid skills
    end;
  end;

  SetLength(Result, Count);
end;

procedure SaveSkill(const ASkill: TSkillDef);
var
  Dir: string;
begin
  ValidateSkillId(ASkill.Id);
  Dir := SkillDirPath(ASkill.Id);
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  // Write SKILL.md
  TFile.WriteAllText(SkillFilePath(ASkill.Id), BuildSkillMd(ASkill), TEncoding.UTF8);

  // Write references/ and examples/ subdirs
  WriteSubDirDocs(Dir, 'references', ASkill.References);
  WriteSubDirDocs(Dir, 'examples', ASkill.Examples);
end;

procedure DeleteSkill(const ASkillId: string);
var
  Dir: string;
begin
  ValidateSkillId(ASkillId);
  Dir := SkillDirPath(ASkillId);
  if DirectoryExists(Dir) then
    TDirectory.Delete(Dir, True);
end;

{ --- Default Skills --- }

procedure SeedDefaults;
var
  Dir: string;

  procedure EnsureSkill(const ASkill: TSkillDef);
  var
    SDir: string;
  begin
    SDir := SkillDirPath(ASkill.Id);
    if DirectoryExists(SDir) then
      Exit;
    SaveSkill(ASkill);
  end;

begin
  Dir := GetSkillDir;
  if not DirectoryExists(Dir) then
    ForceDirectories(Dir);

  // Web Search
  EnsureSkill(TSkillDef.Create('web_search',
    'Web Search',
    'Search the internet for up-to-date information and fetch web page content.',
    'You have web search capabilities. When the user asks about current events, latest information, ' +
    'or topics you are unsure about, proactively use the web_search tool to find answers.' + #10#10 +
    'Guidelines:' + #10 +
    '- Use web_search(query) to search for information. Keep queries concise and specific.' + #10 +
    '- Use web_fetch(url) to read the full content of a relevant page from search results.' + #10 +
    '- Always cite sources by including URLs in your response.' + #10 +
    '- Cross-reference multiple sources when accuracy is critical.' + #10 +
    '- If a search fails, try rephrasing the query or using a different search term.',
    // References
    '--- search-strategies ---' + #10 +
    'Effective search strategies:' + #10 +
    '1. Start broad, then narrow down with specific terms' + #10 +
    '2. Use site: operator for domain-specific searches (e.g. "site:docs.python.org threading")' + #10 +
    '3. Include version numbers when searching for API documentation' + #10 +
    '4. Use quotes for exact phrase matching' + #10 +
    '5. Combine multiple search results to cross-verify facts',
    // Examples
    '--- example-basic-search ---' + #10 +
    'User: "What is the latest version of React?"' + #10 +
    'Agent calls: web_search("React latest version 2026")' + #10 +
    'Agent responds with version number, release date, and source URL.' + #10#10 +
    '--- example-deep-dive ---' + #10 +
    'User: "How does Rust async/await work internally?"' + #10 +
    'Agent calls: web_search("Rust async await internals explanation")' + #10 +
    'Agent then: web_fetch(top_result_url) to read the full article' + #10 +
    'Agent responds with a detailed explanation citing the source.'));

  // Code Review
  EnsureSkill(TSkillDef.Create('code_review',
    'Code Review',
    'Review code for bugs, security issues, performance, and style.',
    'You are performing a code review. Analyze the code thoroughly and provide actionable feedback.' + #10#10 +
    'Review checklist:' + #10 +
    '1. Correctness: Does the code do what it intends? Are there logic errors or edge cases?' + #10 +
    '2. Security: SQL injection, XSS, buffer overflows, hardcoded secrets, unsafe deserialization.' + #10 +
    '3. Performance: Unnecessary loops, memory leaks, N+1 queries, inefficient data structures.' + #10 +
    '4. Readability: Clear naming, appropriate comments, consistent style, reasonable function length.' + #10 +
    '5. Error handling: Are errors caught? Are error messages helpful? Are resources properly freed?' + #10 +
    '6. Testing: Is the code testable? Are edge cases covered?' + #10#10 +
    'Format your review as: [Issue] -> [Location] -> [Severity: High/Medium/Low] -> [Suggestion]',
    // References
    '--- owasp-top-10 ---' + #10 +
    'OWASP Top 10 (2025):' + #10 +
    'A01: Broken Access Control' + #10 +
    'A02: Cryptographic Failures' + #10 +
    'A03: Injection (SQL, XSS, Command)' + #10 +
    'A04: Insecure Design' + #10 +
    'A05: Security Misconfiguration' + #10 +
    'A06: Vulnerable and Outdated Components' + #10 +
    'A07: Authentication Failures' + #10 +
    'A08: Software and Data Integrity Failures' + #10 +
    'A09: Security Logging and Monitoring Failures' + #10 +
    'A10: Server-Side Request Forgery' + #10#10 +
    '--- review-priorities ---' + #10 +
    'Severity levels:' + #10 +
    'High: Security vulnerabilities, data loss, crash bugs, race conditions' + #10 +
    'Medium: Logic errors, missing error handling, performance bottlenecks' + #10 +
    'Low: Style issues, naming, missing comments, minor refactoring opportunities',
    // Examples
    '--- example-sql-injection ---' + #10 +
    'Code: query := "SELECT * FROM users WHERE name = ''" + userName + "''";' + #10 +
    'Issue: SQL Injection vulnerability' + #10 +
    'Location: line 42' + #10 +
    'Severity: High' + #10 +
    'Suggestion: Use parameterized queries: query := "SELECT * FROM users WHERE name = ?";' + #10#10 +
    '--- example-resource-leak ---' + #10 +
    'Code: var FS := TFileStream.Create(path, fmCreate); FS.Write(...);' + #10 +
    'Issue: Resource leak - FS is never freed' + #10 +
    'Location: line 15' + #10 +
    'Severity: Medium' + #10 +
    'Suggestion: Use try-finally: var FS := TFileStream.Create(...); try ... finally FS.Free; end;'));

  // Testing
  EnsureSkill(TSkillDef.Create('testing',
    'Testing',
    'Write unit tests and integration tests with good coverage.',
    'You are helping write tests. Follow these principles:' + #10#10 +
    '1. Arrange-Act-Assert: Structure each test clearly.' + #10 +
    '2. Test one thing per test: Each test should verify a single behavior.' + #10 +
    '3. Name tests descriptively: testMethodName_scenario_expectedResult.' + #10 +
    '4. Cover edge cases: empty inputs, null values, boundary values, error conditions.' + #10 +
    '5. Don''t test implementation details: Test behavior, not internal structure.' + #10 +
    '6. Keep tests independent: No shared mutable state between tests.' + #10 +
    '7. Use setup/teardown for common test fixtures.' + #10 +
    '8. Mock external dependencies, not internal logic.',
    // References
    '--- test-coverage-guide ---' + #10 +
    'Coverage targets:' + #10 +
    '- Critical paths: 100%' + #10 +
    '- Business logic: 80%+' + #10 +
    '- UI/Integration: 50%+' + #10 +
    '- Boilerplate/Getters/Setters: Optional' + #10#10 +
    'Test types by scope:' + #10 +
    '- Unit tests: Single function/method, fast, isolated' + #10 +
    '- Integration tests: Multiple components, medium speed' + #10 +
    '- E2E tests: Full workflow, slow, fragile' + #10#10 +
    '--- mocking-patterns ---' + #10 +
    'When to mock:' + #10 +
    '- External APIs and services' + #10 +
    '- Database connections' + #10 +
    '- File system operations' + #10 +
    '- Time-dependent behavior' + #10 +
    'When NOT to mock:' + #10 +
    '- Internal business logic' + #10 +
    '- Data transformations' + #10 +
    '- Simple utility functions',
    // Examples
    '--- example-unit-test ---' + #10 +
    '// Test: CalculateTotal_WithEmptyItems_ReturnsZero' + #10 +
    'procedure TestCalculateTotalEmpty;' + #10 +
    'var Result: Currency;' + #10 +
    'begin' + #10 +
    '  // Arrange' + #10 +
    '  var Calc := TCalculator.Create;' + #10 +
    '  try' + #10 +
    '    // Act' + #10 +
    '    Result := Calc.CalculateTotal([]);' + #10 +
    '    // Assert' + #10 +
    '    Assert.Equals(0, Result);' + #10 +
    '  finally' + #10 +
    '    Calc.Free;' + #10 +
    '  end;' + #10 +
    'end;'));

  // Refactoring
  EnsureSkill(TSkillDef.Create('refactoring',
    'Refactoring',
    'Refactor code to improve structure, readability, and maintainability.',
    'You are refactoring code. Follow these principles:' + #10#10 +
    'Rules:' + #10 +
    '- Do NOT change external behavior. Refactoring must be behavior-preserving.' + #10 +
    '- Make small, incremental changes. Each step should be independently verifiable.' + #10 +
    '- Run tests after each change if available.' + #10#10 +
    'Common techniques:' + #10 +
    '- Extract Method: Break long functions into smaller, named functions.' + #10 +
    '- Rename: Use descriptive names that reveal intent.' + #10 +
    '- Replace Magic Numbers: Named constants instead of raw values.' + #10 +
    '- Simplify Conditionals: Guard clauses, early returns, polymorphism.' + #10 +
    '- Remove Duplication: DRY principle, extract shared logic.' + #10 +
    '- Reduce Parameters: Introduce parameter objects, use builder pattern.' + #10 +
    '- Move Method: Place methods close to the data they operate on.',
    // References
    '--- code-smells ---' + #10 +
    'Common code smells that indicate refactoring is needed:' + #10 +
    '- Long Method: Function > 20 lines' + #10 +
    '- Large Class: Class with > 10 responsibilities' + #10 +
    '- Long Parameter List: > 4 parameters' + #10 +
    '- Duplicated Code: Same logic in 3+ places' + #10 +
    '- Shotgun Surgery: One change requires editing many files' + #10 +
    '- Feature Envy: Method uses another class more than its own' + #10 +
    '- Data Clumps: Same group of fields appear together often',
    // Examples
    '--- example-extract-method ---' + #10 +
    'Before:' + #10 +
    '  procedure ProcessOrder(Order: TOrder);' + #10 +
    '  begin' + #10 +
    '    // Validate' + #10 +
    '    if Order.Items.Count = 0 then raise Exception.Create(''Empty'');' + #10 +
    '    for var Item in Order.Items do' + #10 +
    '      if Item.Quantity <= 0 then raise Exception.Create(''Invalid qty'');' + #10 +
    '    // Calculate' + #10 +
    '    var Total := 0.0;' + #10 +
    '    for var Item in Order.Items do' + #10 +
    '      Total := Total + Item.Price * Item.Quantity;' + #10 +
    '    // Save' + #10 +
    '    SaveToDatabase(Order);' + #10 +
    '  end;' + #10#10 +
    'After:' + #10 +
    '  procedure ProcessOrder(Order: TOrder);' + #10 +
    '  begin' + #10 +
    '    ValidateOrder(Order);' + #10 +
    '    var Total := CalculateTotal(Order);' + #10 +
    '    SaveToDatabase(Order);' + #10 +
    '  end;'));

  // Documentation
  EnsureSkill(TSkillDef.Create('documentation',
    'Documentation',
    'Write clear documentation including README, API docs, and inline comments.',
    'You are writing documentation. Follow these guidelines:' + #10#10 +
    'README structure:' + #10 +
    '1. Project name and one-line description' + #10 +
    '2. Installation / Getting Started' + #10 +
    '3. Quick Start example' + #10 +
    '4. Configuration options' + #10 +
    '5. API Reference (for libraries)' + #10 +
    '6. Contributing guidelines' + #10#10 +
    'General rules:' + #10 +
    '- Write for the beginner, not the expert.' + #10 +
    '- Show examples, don''t just describe.' + #10 +
    '- Keep comments focused on WHY, not WHAT (code should explain WHAT).' + #10 +
    '- Use consistent terminology throughout.' + #10 +
    '- Document edge cases and gotchas explicitly.',
    // References
    '--- doc-types ---' + #10 +
    'Documentation types by audience:' + #10 +
    '- README: New users, first impression, getting started' + #10 +
    '- API docs: Developers using your library/module' + #10 +
    '- Architecture docs: Team members, new hires' + #10 +
    '- Runbooks: Operations/oncall engineers' + #10 +
    '- ADRs: Architecture Decision Records for future reference' + #10#10 +
    '--- writing-tips ---' + #10 +
    'Tips for clear technical writing:' + #10 +
    '- Use active voice: "The function returns..." not "It is returned by..."' + #10 +
    '- One idea per paragraph' + #10 +
    '- Use code examples with expected output' + #10 +
    '- Include error messages in docs when relevant' + #10 +
    '- Version your docs alongside your code',
    // Examples
    '--- example-api-doc ---' + #10 +
    '## TCalculator.CalculateTotal' + #10 +
    'Calculates the total price of all items in an order.' + #10#10 +
    '```pascal' + #10 +
    'function CalculateTotal(const Items: TArray<TOrderItem>): Currency;' + #10 +
    '```' + #10#10 +
    'Parameters:' + #10 +
    '- Items: Array of order items with Price and Quantity fields' + #10#10 +
    'Returns: Total price as Currency' + #10#10 +
    'Raises: EInvalidOp if any item has negative quantity' + #10#10 +
    'Example:' + #10 +
    '```pascal' + #10 +
    'var Total := Calc.CalculateTotal([TOrderItem.Create(10.0, 2)]);' + #10 +
    '// Total = 20.00' + #10 +
    '```'));
end;

end.
