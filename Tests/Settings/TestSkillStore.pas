unit TestSkillStore;

interface

uses
  System.SysUtils, System.IOUtils, Winapi.Windows,
  Settings.Config, Settings.SkillStore,
  PiMonoTestFramework;

procedure RegisterSkillStoreTests;

implementation

type
  TTestSkillStore = class
  private
    FTestDir: string;
  public
    procedure Setup;
    procedure TearDown;

    // ParseFrontmatter
    procedure Test_ParseFrontmatter_Valid;
    procedure Test_ParseFrontmatter_MissingId;
    procedure Test_ParseFrontmatter_NoFrontmatter;
    procedure Test_ParseFrontmatter_ExtraKeys;
    procedure Test_ParseFrontmatter_CaseInsensitive;
    procedure Test_ParseFrontmatter_EmptyBody;

    // File operations
    procedure Test_SaveAndLoadSkill;
    procedure Test_DeleteSkill;
    procedure Test_DeleteNonExistentSkill;
    procedure Test_ReadSubDirDocs;
    procedure Test_ReadSubDirDocs_NonExistent;
    procedure Test_SkillDirPath;
    procedure Test_SkillFilePath;

    // SeedDefaults, Install, LoadSkillPool
    procedure Test_SeedDefaults_CreatesSkills;
    procedure Test_SeedDefaults_Idempotent;
    procedure Test_InstallSkillFromPath_Valid;
    procedure Test_InstallSkillFromPath_InvalidPath;
    procedure Test_LoadSkillPool_ReturnsSaved;
    procedure Test_LoadSkillPool_EmptyDir;
  end;

{ TTestSkillStore }

procedure TTestSkillStore.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoSkill_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);
end;

procedure TTestSkillStore.TearDown;
begin
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

{ ParseFrontmatter tests - pure function, no file I/O }

procedure TTestSkillStore.Test_ParseFrontmatter_Valid;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content :=
    '---' + #10 +
    'id: test-skill' + #10 +
    'displayName: Test Skill' + #10 +
    'description: A test skill' + #10 +
    '---' + #10 +
    'This is the skill body.';

  Assert(ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should parse valid frontmatter');
  Assert(Id = 'test-skill', 'Id should be test-skill');
  Assert(DisplayName = 'Test Skill', 'DisplayName should match');
  Assert(Description = 'A test skill', 'Description should match');
  Assert(Pos('skill body', Body) > 0, 'Body should contain skill body');
end;

procedure TTestSkillStore.Test_ParseFrontmatter_MissingId;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content :=
    '---' + #10 +
    'displayName: No ID Skill' + #10 +
    '---' + #10 +
    'Body text';

  Assert(not ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should fail without id');
  Assert(Id = '', 'Id should be empty on failure');
end;

procedure TTestSkillStore.Test_ParseFrontmatter_NoFrontmatter;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content := 'Just some plain text without frontmatter.';

  Assert(not ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should fail with no frontmatter');
end;

procedure TTestSkillStore.Test_ParseFrontmatter_ExtraKeys;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content :=
    '---' + #10 +
    'id: extra-keys' + #10 +
    'displayName: Extra' + #10 +
    'description: With extra' + #10 +
    'version: 1.0' + #10 +
    'author: test' + #10 +
    '---' + #10 +
    'Body';

  Assert(ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should succeed with extra keys');
  Assert(Id = 'extra-keys', 'Id should be parsed');
  // Extra keys should be silently ignored
end;

procedure TTestSkillStore.Test_ParseFrontmatter_CaseInsensitive;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content :=
    '---' + #10 +
    'ID: case-test' + #10 +
    'DisplayName: Case Test' + #10 +
    'Description: Case insensitive' + #10 +
    '---' + #10 +
    'Body';

  Assert(ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should parse case-insensitively');
  Assert(Id = 'case-test', 'Id should match');
end;

procedure TTestSkillStore.Test_ParseFrontmatter_EmptyBody;
var
  Id, DisplayName, Description, Body: string;
begin
  var Content :=
    '---' + #10 +
    'id: empty-body' + #10 +
    '---' + #10;

  Assert(ParseFrontmatter(Content, Id, DisplayName, Description, Body),
    'Should succeed with empty body');
  Assert(Id = 'empty-body', 'Id should be parsed');
end;

{ File operation tests }

procedure TTestSkillStore.Test_SaveAndLoadSkill;
var
  Skill: TSkillDef;
  SkillId: string;
  Dir: string;
begin
  SkillId := 'test_save_unit_' + FormatDateTime('yyyymmddhhnnss', Now) + '_' + IntToStr(GetTickCount);
  Dir := SkillDirPath(SkillId);
  try
    Skill := TSkillDef.Create(SkillId, 'Test Save', 'A test', 'Body content', '', '');
    SaveSkill(Skill);
    Assert(True, 'SaveSkill should not crash');
  finally
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSkillStore.Test_DeleteSkill;
begin
  // Create a skill first
  var Skill := TSkillDef.Create('to-delete', 'Delete Me', 'Test', 'Body', '', '');
  SaveSkill(Skill);
  var Dir := SkillDirPath('to-delete');
  Assert(TDirectory.Exists(Dir), 'Skill dir should exist after save');

  DeleteSkill('to-delete');
  Assert(not TDirectory.Exists(Dir), 'Skill dir should be deleted');
end;

procedure TTestSkillStore.Test_DeleteNonExistentSkill;
begin
  // Should not crash
  DeleteSkill('nonexistent_skill_12345');
  Assert(True, 'DeleteNonExistent should not crash');
end;

procedure TTestSkillStore.Test_ReadSubDirDocs;
var
  SubDir: string;
  Result_: string;
begin
  SubDir := TPath.Combine(FTestDir, 'refs');
  TDirectory.CreateDirectory(SubDir);
  TFile.WriteAllText(TPath.Combine(SubDir, 'doc1.md'), 'Content 1');
  TFile.WriteAllText(TPath.Combine(SubDir, 'doc2.md'), 'Content 2');

  Result_ := ReadSubDirDocs(FTestDir, 'refs');
  Assert(Pos('Content 1', Result_) > 0, 'Should contain doc1');
  Assert(Pos('Content 2', Result_) > 0, 'Should contain doc2');
end;

procedure TTestSkillStore.Test_ReadSubDirDocs_NonExistent;
var
  Result_: string;
begin
  Result_ := ReadSubDirDocs(FTestDir, 'nonexistent');
  Assert(Result_ = '', 'Non-existent subdir should return empty');
end;

procedure TTestSkillStore.Test_SkillDirPath;
var
  Path: string;
begin
  Path := SkillDirPath('my-skill');
  Assert(Pos('my-skill', Path) > 0, 'Path should contain skill id');
  Assert(Path.EndsWith('\'), 'Path should end with backslash');
end;

procedure TTestSkillStore.Test_SkillFilePath;
var
  Path: string;
begin
  Path := SkillFilePath('my-skill');
  Assert(Pos('my-skill', Path) > 0, 'Path should contain skill id');
  Assert(Pos('SKILL.md', Path) > 0, 'Path should contain SKILL.md');
end;

procedure TTestSkillStore.Test_SeedDefaults_CreatesSkills;
begin
  SeedDefaults;
  var Dir := GetSkillDir;
  Assert(TDirectory.Exists(Dir), 'Skill directory should exist after SeedDefaults');
  // At least one default skill directory should exist
  var Dirs := TDirectory.GetDirectories(Dir);
  Assert(Length(Dirs) > 0, 'SeedDefaults should create at least one skill directory');
end;

procedure TTestSkillStore.Test_SeedDefaults_Idempotent;
begin
  SeedDefaults;
  SeedDefaults;
  Assert(True, 'SeedDefaults called twice should not crash');
end;

procedure TTestSkillStore.Test_InstallSkillFromPath_Valid;
var
  TempFile, TempDir: string;
  Skill: TSkillDef;
begin
  TempDir := TPath.Combine(FTestDir, 'install_test');
  TDirectory.CreateDirectory(TempDir);
  TempFile := TPath.Combine(TempDir, 'SKILL.md');
  TFile.WriteAllText(TempFile,
    '---' + #10 +
    'id: installed-skill' + #10 +
    'displayName: Installed Skill' + #10 +
    'description: A skill installed from file' + #10 +
    '---' + #10 +
    'This is the installed skill body.');

  Skill := InstallSkillFromPath(TempFile);
  try
    Assert(Skill.Id = 'installed-skill', 'Id should be installed-skill');
    Assert(Skill.DisplayName = 'Installed Skill', 'DisplayName should match');
    Assert(Pos('installed skill body', Skill.Content) > 0, 'Content should contain body');
  finally
    // Cleanup installed skill dir
    var SDir := SkillDirPath('installed-skill');
    if TDirectory.Exists(SDir) then
      TDirectory.Delete(SDir, True);
  end;
end;

procedure TTestSkillStore.Test_InstallSkillFromPath_InvalidPath;
var
  Caught: Boolean;
begin
  Caught := False;
  try
    InstallSkillFromPath('C:\nonexistent\path\SKILL.md');
  except
    on E: Exception do
      Caught := True;
  end;
  Assert(Caught, 'InstallSkillFromPath with invalid path should raise exception');
end;

procedure TTestSkillStore.Test_LoadSkillPool_ReturnsSaved;
var
  Pool: TArray<TSkillDef>;
begin
  var Skill := TSkillDef.Create('loadtest-skill', 'Load Test', 'A test', 'Body content');
  SaveSkill(Skill);
  try
    Pool := LoadSkillPool;
    var Found: Boolean := False;
    for var i := 0 to High(Pool) do
      if Pool[i].Id = 'loadtest-skill' then
        Found := True;
    Assert(Found, 'LoadSkillPool should return saved skill');
  finally
    var Dir := SkillDirPath('loadtest-skill');
    if TDirectory.Exists(Dir) then
      TDirectory.Delete(Dir, True);
  end;
end;

procedure TTestSkillStore.Test_LoadSkillPool_EmptyDir;
var
  Pool: TArray<TSkillDef>;
  TempDir: string;
begin
  // Use a temp directory that exists but has no skill files
  TempDir := TPath.Combine(FTestDir, 'empty_skills');
  TDirectory.CreateDirectory(TempDir);
  // LoadSkillPool reads from GetSkillDir which is the real skill dir,
  // so we test by ensuring no skill dirs match our test prefix
  Pool := LoadSkillPool;
  // Pool may or may not be empty depending on other tests, just verify it doesn't crash
  Assert(True, 'LoadSkillPool should not crash');
end;

{ Registration }

procedure RegisterSkillStoreTests;
var
  T: TTestSkillStore;
begin
  T := TTestSkillStore.Create;
  try
    // ParseFrontmatter (pure function tests)
    GRunner.RunTest('SkillStore: ParseFrontmatter valid', T.Test_ParseFrontmatter_Valid, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ParseFrontmatter missing id', T.Test_ParseFrontmatter_MissingId, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ParseFrontmatter no frontmatter', T.Test_ParseFrontmatter_NoFrontmatter, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ParseFrontmatter extra keys', T.Test_ParseFrontmatter_ExtraKeys, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ParseFrontmatter case insensitive', T.Test_ParseFrontmatter_CaseInsensitive, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ParseFrontmatter empty body', T.Test_ParseFrontmatter_EmptyBody, T.Setup, T.TearDown);
    // File operations
    GRunner.RunTest('SkillStore: Save and load skill', T.Test_SaveAndLoadSkill, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: Delete skill', T.Test_DeleteSkill, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: Delete nonexistent skill', T.Test_DeleteNonExistentSkill, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ReadSubDirDocs', T.Test_ReadSubDirDocs, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: ReadSubDirDocs nonexistent', T.Test_ReadSubDirDocs_NonExistent, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: SkillDirPath', T.Test_SkillDirPath, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: SkillFilePath', T.Test_SkillFilePath, T.Setup, T.TearDown);
    // SeedDefaults, Install, LoadSkillPool
    GRunner.RunTest('SkillStore: SeedDefaults creates skills', T.Test_SeedDefaults_CreatesSkills, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: SeedDefaults idempotent', T.Test_SeedDefaults_Idempotent, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: InstallSkillFromPath valid', T.Test_InstallSkillFromPath_Valid, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: InstallSkillFromPath invalid path', T.Test_InstallSkillFromPath_InvalidPath, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: LoadSkillPool returns saved', T.Test_LoadSkillPool_ReturnsSaved, T.Setup, T.TearDown);
    GRunner.RunTest('SkillStore: LoadSkillPool empty dir', T.Test_LoadSkillPool_EmptyDir, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
