unit TestAnimations;

{ Tests for UI.Animations - animation state classes and easing math }

interface

uses
  System.SysUtils, System.Math, Vcl.Graphics,
  UI.Animations,
  PiMonoTestFramework;

procedure RegisterAnimationTests;

implementation

type
  TTestAnimationState = class
  public
    procedure Test_ActiveAnimation_Create;
    procedure Test_FloatAnimation_Fields;
    procedure Test_ColorAnimation_Fields;
    procedure Test_AnimEase_EnumValues;
  end;

  TTestEasingMath = class
  public
    procedure Test_Linear_t0;
    procedure Test_Linear_t1;
    procedure Test_Linear_t05;
    procedure Test_Quad_t0;
    procedure Test_Quad_t1;
    procedure Test_Cubic_t0;
    procedure Test_Cubic_t1;
    procedure Test_Circ_t0;
    procedure Test_Circ_t1;
  end;

  TTestAnimationLifecycle = class
  public
    procedure Setup;
    procedure TearDown;
    procedure Test_CancelAll_Clears;
    procedure Test_IsAnimationRunning_False;
    procedure Test_AnimateFloat_ReturnsID;
    procedure Test_AnimateColor_ReturnsID;
    procedure Test_CancelNonExistent_NoCrash;
  end;

var
  FLastFloatValue: Double;
  FLastColorValue: TColor;
  FFinishCalled: Boolean;

procedure FloatCallback(Value: Double);
begin
  FLastFloatValue := Value;
end;

procedure ColorCallbackProc(Color: TColor);
begin
  FLastColorValue := Color;
end;

procedure FinishCallback;
begin
  FFinishCalled := True;
end;

{ TTestAnimationState }

procedure TTestAnimationState.Test_ActiveAnimation_Create;
var
  Anim: TActiveAnimation;
begin
  Anim := TActiveAnimation.Create;
  try
    Assert(Anim.Finished = False, 'New animation should not be finished');
    Assert(Anim.DurationMs = 0, 'Default DurationMs should be 0');
    Assert(Anim.ID = 0, 'Default ID should be 0');
    Assert(Anim.Ease = aeLinear, 'Default Ease should be aeLinear');
    Assert(not Assigned(Anim.OnFinish), 'OnFinish should be nil');
  finally
    Anim.Free;
  end;
end;

procedure TTestAnimationState.Test_FloatAnimation_Fields;
var
  Anim: TFloatAnimation;
begin
  Anim := TFloatAnimation.Create;
  try
    Anim.FromVal := 10.0;
    Anim.ToVal := 20.0;
    Anim.DurationMs := 500;
    Anim.Ease := aeQuad;
    Assert(Abs(Anim.FromVal - 10.0) < 0.001, 'FromVal should be 10');
    Assert(Abs(Anim.ToVal - 20.0) < 0.001, 'ToVal should be 20');
    Assert(Anim.DurationMs = 500, 'DurationMs should be 500');
    Assert(Anim.Ease = aeQuad, 'Ease should be aeQuad');
    Assert(not Assigned(Anim.OnUpdate), 'OnUpdate should be nil initially');
  finally
    Anim.Free;
  end;
end;

procedure TTestAnimationState.Test_ColorAnimation_Fields;
var
  Anim: TColorAnimation;
begin
  Anim := TColorAnimation.Create;
  try
    Anim.FromR := 255; Anim.FromG := 0; Anim.FromB := 0;
    Anim.ToR := 0; Anim.ToG := 0; Anim.ToB := 255;
    Assert(Anim.FromR = 255, 'FromR should be 255');
    Assert(Anim.FromG = 0, 'FromG should be 0');
    Assert(Anim.FromB = 0, 'FromB should be 0');
    Assert(Anim.ToR = 0, 'ToR should be 0');
    Assert(Anim.ToG = 0, 'ToG should be 0');
    Assert(Anim.ToB = 255, 'ToB should be 255');
  finally
    Anim.Free;
  end;
end;

procedure TTestAnimationState.Test_AnimEase_EnumValues;
begin
  Assert(Ord(aeLinear) = 0, 'aeLinear should be 0');
  Assert(Ord(aeQuad) = 1, 'aeQuad should be 1');
  Assert(Ord(aeCubic) = 2, 'aeCubic should be 2');
  Assert(Ord(aeCirc) = 3, 'aeCirc should be 3');
end;

{ TTestEasingMath }
{ Tests for ApplyEase — calls the actual easing function from UI.Animations. }

procedure TTestEasingMath.Test_Linear_t0;
begin
  Assert(Abs(ApplyEase(0.0, aeLinear) - 0.0) < 0.001, 'Linear(0) should be 0');
end;

procedure TTestEasingMath.Test_Linear_t1;
begin
  Assert(Abs(ApplyEase(1.0, aeLinear) - 1.0) < 0.001, 'Linear(1) should be 1');
end;

procedure TTestEasingMath.Test_Linear_t05;
begin
  Assert(Abs(ApplyEase(0.5, aeLinear) - 0.5) < 0.001, 'Linear(0.5) should be 0.5');
end;

procedure TTestEasingMath.Test_Quad_t0;
begin
  Assert(Abs(ApplyEase(0.0, aeQuad) - 0.0) < 0.001, 'Quad(0) should be 0');
end;

procedure TTestEasingMath.Test_Quad_t1;
begin
  Assert(Abs(ApplyEase(1.0, aeQuad) - 1.0) < 0.001, 'Quad(1) should be 1');
end;

procedure TTestEasingMath.Test_Cubic_t0;
begin
  Assert(Abs(ApplyEase(0.0, aeCubic) - 0.0) < 0.001, 'Cubic(0) should be 0');
end;

procedure TTestEasingMath.Test_Cubic_t1;
begin
  Assert(Abs(ApplyEase(1.0, aeCubic) - 1.0) < 0.001, 'Cubic(1) should be 1');
end;

procedure TTestEasingMath.Test_Circ_t0;
begin
  Assert(Abs(ApplyEase(0.0, aeCirc) - 0.0) < 0.001, 'Circ(0) should be 0');
end;

procedure TTestEasingMath.Test_Circ_t1;
begin
  Assert(Abs(ApplyEase(1.0, aeCirc) - 1.0) < 0.001, 'Circ(1) should be 1');
end;

{ TTestAnimationLifecycle }

procedure TTestAnimationLifecycle.Setup;
begin
  CancelAllAnimations;
  FLastFloatValue := -1;
  FLastColorValue := clNone;
  FFinishCalled := False;
end;

procedure TTestAnimationLifecycle.TearDown;
begin
  CancelAllAnimations;
end;

procedure TTestAnimationLifecycle.Test_CancelAll_Clears;
begin
  CancelAllAnimations;
  // Should not crash, and all animations should be gone
  Assert(not IsAnimationRunning(9999), 'After CancelAll, no animations running');
end;

procedure TTestAnimationLifecycle.Test_IsAnimationRunning_False;
begin
  Assert(not IsAnimationRunning(-1), 'Non-existent ID should return False');
  Assert(not IsAnimationRunning(0), 'Non-existent ID 0 should return False');
  Assert(not IsAnimationRunning(999999), 'Large non-existent ID should return False');
end;

procedure TTestAnimationLifecycle.Test_AnimateFloat_ReturnsID;
var
  ID: Integer;
begin
  ID := AnimateFloat(0, 100, 1000, aeLinear, FloatCallback);
  Assert(ID > 0, 'AnimateFloat should return positive ID');
  Assert(IsAnimationRunning(ID), 'New animation should be running');
  CancelAnimation(ID);
end;

procedure TTestAnimationLifecycle.Test_AnimateColor_ReturnsID;
var
  ID: Integer;
begin
  ID := AnimateColor(clBlack, clWhite, 1000, aeLinear,
    procedure(Color: TColor) begin FLastColorValue := Color; end);
  Assert(ID > 0, 'AnimateColor should return positive ID');
  Assert(IsAnimationRunning(ID), 'New color animation should be running');
  CancelAnimation(ID);
end;

procedure TTestAnimationLifecycle.Test_CancelNonExistent_NoCrash;
begin
  // Should not crash
  CancelAnimation(-1);
  CancelAnimation(0);
  CancelAnimation(999999);
  Assert(True, 'CancelAnimation on non-existent IDs should not crash');
end;

{ Registration }

procedure RegisterAnimationTests;
var
  TAS: TTestAnimationState;
  TE: TTestEasingMath;
  TL: TTestAnimationLifecycle;
begin
  TAS := TTestAnimationState.Create;
  try
    GRunner.RunTest('Animations: ActiveAnimation create', TAS.Test_ActiveAnimation_Create);
    GRunner.RunTest('Animations: FloatAnimation fields', TAS.Test_FloatAnimation_Fields);
    GRunner.RunTest('Animations: ColorAnimation fields', TAS.Test_ColorAnimation_Fields);
    GRunner.RunTest('Animations: AnimEase enum values', TAS.Test_AnimEase_EnumValues);
  finally
    TAS.Free;
  end;

  TE := TTestEasingMath.Create;
  try
    GRunner.RunTest('Animations: Linear t=0', TE.Test_Linear_t0);
    GRunner.RunTest('Animations: Linear t=1', TE.Test_Linear_t1);
    GRunner.RunTest('Animations: Linear t=0.5', TE.Test_Linear_t05);
    GRunner.RunTest('Animations: Quad t=0', TE.Test_Quad_t0);
    GRunner.RunTest('Animations: Quad t=1', TE.Test_Quad_t1);
    GRunner.RunTest('Animations: Cubic t=0', TE.Test_Cubic_t0);
    GRunner.RunTest('Animations: Cubic t=1', TE.Test_Cubic_t1);
    GRunner.RunTest('Animations: Circ t=0', TE.Test_Circ_t0);
    GRunner.RunTest('Animations: Circ t=1', TE.Test_Circ_t1);
  finally
    TE.Free;
  end;

  TL := TTestAnimationLifecycle.Create;
  try
    GRunner.RunTest('Animations: CancelAll clears', TL.Test_CancelAll_Clears, TL.Setup, TL.TearDown);
    GRunner.RunTest('Animations: IsRunning false for unknown', TL.Test_IsAnimationRunning_False, TL.Setup, TL.TearDown);
    GRunner.RunTest('Animations: AnimateFloat returns ID', TL.Test_AnimateFloat_ReturnsID, TL.Setup, TL.TearDown);
    GRunner.RunTest('Animations: AnimateColor returns ID', TL.Test_AnimateColor_ReturnsID, TL.Setup, TL.TearDown);
    GRunner.RunTest('Animations: Cancel non-existent no crash', TL.Test_CancelNonExistent_NoCrash, TL.Setup, TL.TearDown);
  finally
    TL.Free;
  end;
end;

end.
