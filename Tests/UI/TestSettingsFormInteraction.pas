unit TestSettingsFormInteraction;

{ Settings form interaction tests.
  Creates TSettingsForm in memory with a real TSettingsManager backed by temp dir.
  Tests tab switching, field population, save/cancel, profile CRUD, skill CRUD. }

interface

uses
  System.SysUtils, System.IOUtils, Winapi.Windows,
  Vcl.Forms,
  Settings.Config, Settings.SettingsManager, Settings.SkillStore,
  UI.SettingsForm,
  PiMonoTestFramework;

procedure RegisterSettingsFormInteractionTests;

implementation

type
  // Protected access hack: descendant in same unit sees protected members
  TSettingsFormAccess = class(TSettingsForm);

  TTestSettingsFormInteraction = class
  private
    FTestDir: string;
    FSettingsManager: TSettingsManager;
    FForm: TSettingsFormAccess;
  public
    procedure Setup;
    procedure TearDown;

    { Form lifecycle }
    procedure Test_FormCreate_HasTabs;
    procedure Test_FormCreate_HasSaveCancelButtons;

    { Tab navigation }
    procedure Test_TabSwitch_ToModelTab;
    procedure Test_TabSwitch_ToUITab;
    procedure Test_TabSwitch_ToProfilesTab;

    { Field population }
    procedure Test_LoadSettings_ApiEndpointPopulated;
    procedure Test_LoadSettings_ModelNamePopulated;
    procedure Test_LoadSettings_ThemePopulated;

    { Save / Cancel }
    procedure Test_Save_UpdatesApiKey;
    procedure Test_Save_UpdatesModelName;
    procedure Test_Save_UpdatesTheme;
    procedure Test_Cancel_DoesNotModifySettings;

    { Profiles }
    procedure Test_Profiles_HasDefaultProfile;
    procedure Test_AddProfile_IncreasesCount;

    { Skills }
    procedure Test_Skills_NewSkill_IncreasesListCount;
  end;

{ TTestSettingsFormInteraction }

procedure TTestSettingsFormInteraction.Setup;
begin
  FTestDir := TPath.Combine(TPath.GetTempPath,
    'PiMonoSettings_' + FormatDateTime('yyyymmddhhnnsszzz', Now) + '_' + IntToStr(GetTickCount));
  TDirectory.CreateDirectory(FTestDir);

  FSettingsManager := TSettingsManager.Create;
  FSettingsManager.Initialize(FTestDir);

  // Create the form the same way Execute does (but without ShowModal)
  FForm := TSettingsFormAccess.Create(nil);
  FForm.FSettingsManager := FSettingsManager;
  FForm.LoadSettings;
end;

procedure TTestSettingsFormInteraction.TearDown;
begin
  FForm.Free;
  FSettingsManager.Free;
  try
    if TDirectory.Exists(FTestDir) then
      TDirectory.Delete(FTestDir, True);
  except
  end;
end;

{ --- Form lifecycle --- }

procedure TTestSettingsFormInteraction.Test_FormCreate_HasTabs;
begin
  Assert(FForm.PageControl <> nil, 'PageControl should exist');
  Assert(FForm.PageControl.PageCount >= 6, 'Should have at least 6 tabs, got ' + IntToStr(FForm.PageControl.PageCount));
end;

procedure TTestSettingsFormInteraction.Test_FormCreate_HasSaveCancelButtons;
begin
  Assert(FForm.BtnSave <> nil, 'BtnSave should exist');
  Assert(FForm.BtnCancel <> nil, 'BtnCancel should exist');
end;

{ --- Tab navigation --- }

procedure TTestSettingsFormInteraction.Test_TabSwitch_ToModelTab;
begin
  FForm.PageControl.ActivePageIndex := 1; // Profiles tab
  Assert(FForm.PageControl.ActivePageIndex = 1, 'Active page should be 1');

  FForm.PageControl.ActivePageIndex := 2; // Model tab
  Assert(FForm.PageControl.ActivePageIndex = 2, 'Active page should be 2');
end;

procedure TTestSettingsFormInteraction.Test_TabSwitch_ToUITab;
begin
  FForm.PageControl.ActivePageIndex := 3; // UI tab
  Assert(FForm.PageControl.ActivePageIndex = 3, 'Active page should be 3');
end;

procedure TTestSettingsFormInteraction.Test_TabSwitch_ToProfilesTab;
begin
  FForm.PageControl.ActivePageIndex := 1; // Profiles tab
  Assert(FForm.PageControl.ActivePageIndex = 1, 'Active page should be Profiles');
end;

{ --- Field population --- }

procedure TTestSettingsFormInteraction.Test_LoadSettings_ApiEndpointPopulated;
begin
  // Default config has a non-empty API endpoint
  Assert(FForm.EdtApiEndpoint <> nil, 'EdtApiEndpoint should exist');
  Assert(FForm.EdtApiEndpoint.Text <> '', 'API endpoint should be populated from config');
end;

procedure TTestSettingsFormInteraction.Test_LoadSettings_ModelNamePopulated;
begin
  Assert(FForm.EdtModelName <> nil, 'EdtModelName should exist');
  Assert(FForm.EdtModelName.Text <> '', 'Model name should be populated from config');
end;

procedure TTestSettingsFormInteraction.Test_LoadSettings_ThemePopulated;
begin
  Assert(FForm.CmbTheme <> nil, 'CmbTheme should exist');
  Assert(FForm.CmbTheme.ItemIndex >= 0, 'Theme combo should have a selected item');
end;

{ --- Save / Cancel --- }

procedure TTestSettingsFormInteraction.Test_Save_UpdatesApiKey;
var
  NewKey: string;
begin
  NewKey := 'sk-test-key-12345';
  FForm.EdtApiKey.Text := NewKey;

  FForm.BtnSaveClick(nil);

  // Reload settings and verify
  FSettingsManager.Initialize(FTestDir);
  Assert(FSettingsManager.Config.Api.ApiKey = NewKey,
    'API key should be updated after save, got: ' + FSettingsManager.Config.Api.ApiKey);
end;

procedure TTestSettingsFormInteraction.Test_Save_UpdatesModelName;
var
  NewModel: string;
begin
  NewModel := 'claude-test-model';
  FForm.EdtModelName.Text := NewModel;

  FForm.BtnSaveClick(nil);

  FSettingsManager.Initialize(FTestDir);
  Assert(FSettingsManager.Config.Model.Name = NewModel,
    'Model name should be updated after save, got: ' + FSettingsManager.Config.Model.Name);
end;

procedure TTestSettingsFormInteraction.Test_Save_UpdatesTheme;
begin
  FForm.CmbTheme.ItemIndex := 1; // Light

  FForm.BtnSaveClick(nil);

  FSettingsManager.Initialize(FTestDir);
  Assert(FSettingsManager.Config.UI.Theme = 'Light',
    'Theme should be Light after save, got: ' + FSettingsManager.Config.UI.Theme);
end;

procedure TTestSettingsFormInteraction.Test_Cancel_DoesNotModifySettings;
var
  OriginalModel: string;
begin
  OriginalModel := FSettingsManager.Config.Model.Name;

  // Change a field
  FForm.EdtModelName.Text := 'should-not-be-saved';

  // Cancel
  FForm.BtnCancelClick(nil);

  // Reload and verify original is preserved
  FSettingsManager.Initialize(FTestDir);
  Assert(FSettingsManager.Config.Model.Name = OriginalModel,
    'Model name should NOT change after cancel');
end;

{ --- Profiles --- }

procedure TTestSettingsFormInteraction.Test_Profiles_HasDefaultProfile;
begin
  Assert(Length(FForm.FProfiles) >= 1, 'Should have at least 1 profile, got ' + IntToStr(Length(FForm.FProfiles)));
  Assert(FForm.LstProfiles.Items.Count >= 1, 'Profile list should have at least 1 item');
end;

procedure TTestSettingsFormInteraction.Test_AddProfile_IncreasesCount;
var
  InitialCount: Integer;
begin
  InitialCount := Length(FForm.FProfiles);
  FForm.BtnAddProfileClick(nil);
  Assert(Length(FForm.FProfiles) = InitialCount + 1,
    'Profile count should increase by 1, got ' + IntToStr(Length(FForm.FProfiles)));
end;

{ --- Skills --- }

procedure TTestSettingsFormInteraction.Test_Skills_NewSkill_IncreasesListCount;
var
  InitialCount: Integer;
begin
  InitialCount := FForm.LstSkills.Items.Count;
  FForm.BtnSkillNewClick(nil);
  Assert(FForm.LstSkills.Items.Count = InitialCount + 1,
    'Skill list should increase by 1, got ' + IntToStr(FForm.LstSkills.Items.Count));
end;

{ Registration }

procedure RegisterSettingsFormInteractionTests;
var
  T: TTestSettingsFormInteraction;
begin
  T := TTestSettingsFormInteraction.Create;
  try
    GRunner.RunTest('SettingsInteract: form has tabs', T.Test_FormCreate_HasTabs, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: form has save/cancel', T.Test_FormCreate_HasSaveCancelButtons, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: tab switch to model', T.Test_TabSwitch_ToModelTab, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: tab switch to UI', T.Test_TabSwitch_ToUITab, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: tab switch to profiles', T.Test_TabSwitch_ToProfilesTab, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: API endpoint populated', T.Test_LoadSettings_ApiEndpointPopulated, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: model name populated', T.Test_LoadSettings_ModelNamePopulated, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: theme populated', T.Test_LoadSettings_ThemePopulated, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: save updates API key', T.Test_Save_UpdatesApiKey, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: save updates model name', T.Test_Save_UpdatesModelName, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: save updates theme', T.Test_Save_UpdatesTheme, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: cancel preserves settings', T.Test_Cancel_DoesNotModifySettings, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: profiles has default', T.Test_Profiles_HasDefaultProfile, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: add profile increases count', T.Test_AddProfile_IncreasesCount, T.Setup, T.TearDown);
    GRunner.RunTest('SettingsInteract: new skill increases list', T.Test_Skills_NewSkill_IncreasesListCount, T.Setup, T.TearDown);
  finally
    T.Free;
  end;
end;

end.
