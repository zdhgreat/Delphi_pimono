unit Utils.SkiaDraw;

{ Skia-based anti-aliased drawing utilities for VCL.
  Uses TBitmap.SkiaDraw for offscreen rasterization.
  Supports solid fills, linear gradients, and drop shadows. }

interface

uses
  System.SysUtils, System.UITypes, System.Types,
  Winapi.Windows,
  System.Skia,
  Vcl.Graphics,
  Vcl.Skia;

{ Convert VCL TColor to Skia TAlphaColor (fully opaque) }
function ColorToAlphaColor(AColor: TColor): TAlphaColor;

{ Render an anti-aliased rounded rect into an existing TBitmap
  using TBitmap.SkiaDraw. Clears the bitmap first. }
procedure DrawSkiaRoundRectOnBitmap(ABitmap: TBitmap;
  ARadius: Single; AFillColor: TColor;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

{ Render an anti-aliased rounded rect onto a VCL TCanvas.
  Creates a temporary TBitmap, uses SkiaDraw, then blits. }
procedure DrawSkiaRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

{ Render a gradient-filled rounded rect onto a VCL TCanvas.
  AColor1 = start color, AColor2 = end color (left to right). }
procedure DrawSkiaGradientRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AColor1, AColor2: TColor;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

{ Render a gradient-filled rounded rect into an existing TBitmap. }
procedure DrawSkiaGradientRoundRectOnBitmap(ABitmap: TBitmap;
  ARadius: Single; AColor1, AColor2: TColor;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

{ Draw a drop shadow behind a rounded rect area on ACanvas.
  AShadowColor = shadow color with alpha, AShadowRadius = blur radius,
  AOffsetX/Y = shadow offset. The shadow is drawn in the padded area. }
procedure DrawSkiaShadowRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AShadowColor: TColor; AShadowRadius: Single = 4.0;
  AOffsetX: Single = 0; AOffsetY: Single = 2.0);

{ Draw shadow to a bitmap, bitmap size should include padding for shadow. }
procedure DrawSkiaShadowRoundRectOnBitmap(ABitmap: TBitmap;
  const AInnerRect: TRectF; ARadius: Single;
  AShadowColor: TColor; AShadowRadius: Single = 4.0;
  AOffsetX: Single = 0; AOffsetY: Single = 2.0);

{ Combined: shadow + solid fill rounded rect onto canvas.
  AShadowPadding = extra pixels around rect for shadow. }
procedure DrawSkiaRoundRectWithShadow(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  AShadowColor: TColor; AShadowRadius: Single = 4.0;
  AOffsetX: Single = 0; AOffsetY: Single = 2.0;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

{ Combined: shadow + gradient fill rounded rect onto canvas. }
procedure DrawSkiaGradientRoundRectWithShadow(ACanvas: TCanvas;
  const ARect: TRect; ARadius: Single;
  AColor1, AColor2: TColor;
  AShadowColor: TColor; AShadowRadius: Single = 4.0;
  AOffsetX: Single = 0; AOffsetY: Single = 2.0;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

type
  { Multi-level shadow parameters for visual depth hierarchy }
  TShadowLevel = record
    Blur: Single;
    OffsetX: Single;
    OffsetY: Single;
  end;

const
  { Level 1: Subtle shadow for code blocks, suggestion cards, list items }
  SHADOW_1: TShadowLevel = (Blur: 3; OffsetX: 0; OffsetY: 1);
  { Level 2: Medium shadow for message bubbles, input card }
  SHADOW_2: TShadowLevel = (Blur: 6; OffsetX: 0; OffsetY: 2);
  { Level 3: Strong shadow for floating elements, send button }
  SHADOW_3: TShadowLevel = (Blur: 12; OffsetX: 0; OffsetY: 4);

{ Draw a shadow with a named level preset }
procedure DrawSkiaRoundRectWithShadowLevel(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  AShadowColor: TColor; ALevel: TShadowLevel;
  ABorderColor: TColor = clNone; ABorderWidth: Single = 1.0);

implementation

const
  MAX_SKIA_BITMAP_SIZE = 4096;

function ColorToAlphaColor(AColor: TColor): TAlphaColor;
var
  R, G, B: Byte;
begin
  if AColor = clNone then
    Exit(TAlphaColorRec.Null);
  // Handle system colors (negative values)
  if AColor < 0 then
    AColor := GetSysColor(AColor and $00FFFFFF);
  R := GetRValue(AColor);
  G := GetGValue(AColor);
  B := GetBValue(AColor);
  Result := TAlphaColor($FF000000 or (R shl 16) or (G shl 8) or B);
end;

procedure DrawSkiaRoundRectOnBitmap(ABitmap: TBitmap;
  ARadius: Single; AFillColor: TColor;
  ABorderColor: TColor; ABorderWidth: Single);
var
  FillAC, BorderAC: TAlphaColor;
  W, H: Single;
begin
  FillAC := ColorToAlphaColor(AFillColor);
  BorderAC := ColorToAlphaColor(ABorderColor);
  W := ABitmap.Width;
  H := ABitmap.Height;

  ABitmap.SkiaDraw(
    procedure(const ACanvas: ISkCanvas)
    var
      Paint: ISkPaint;
      R: TRectF;
    begin
      // Clear to transparent
      ACanvas.Clear(TAlphaColorRec.Null);

      // Fill rounded rect
      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Fill;
      Paint.Color := FillAC;
      Paint.AntiAlias := True;
      R := TRectF.Create(0.5, 0.5, W - 0.5, H - 0.5);
      ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

      // Border
      if ABorderColor <> clNone then
      begin
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Stroke;
        Paint.Color := BorderAC;
        Paint.StrokeWidth := ABorderWidth;
        Paint.AntiAlias := True;
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);
      end;
    end);
end;

procedure DrawSkiaRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  ABorderColor: TColor; ABorderWidth: Single);
var
  Bmp: Vcl.Graphics.TBitmap;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;
  if (ARect.Width > MAX_SKIA_BITMAP_SIZE) or (ARect.Height > MAX_SKIA_BITMAP_SIZE) then
  begin
    // Fallback: draw directly without bitmap for very large rects
    ACanvas.Brush.Color := AFillColor;
    ACanvas.FillRect(ARect);
    Exit;
  end;
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(ARect.Width, ARect.Height);
    DrawSkiaRoundRectOnBitmap(Bmp, ARadius, AFillColor, ABorderColor, ABorderWidth);
    ACanvas.Draw(ARect.Left, ARect.Top, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure DrawSkiaGradientRoundRectOnBitmap(ABitmap: TBitmap;
  ARadius: Single; AColor1, AColor2: TColor;
  ABorderColor: TColor; ABorderWidth: Single);
var
  AC1, AC2, BorderAC: TAlphaColor;
  W, H: Single;
begin
  AC1 := ColorToAlphaColor(AColor1);
  AC2 := ColorToAlphaColor(AColor2);
  BorderAC := ColorToAlphaColor(ABorderColor);
  W := ABitmap.Width;
  H := ABitmap.Height;

  ABitmap.SkiaDraw(
    procedure(const ACanvas: ISkCanvas)
    var
      Paint: ISkPaint;
      R: TRectF;
    begin
      ACanvas.Clear(TAlphaColorRec.Null);

      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Fill;
      Paint.AntiAlias := True;
      // Left-to-right linear gradient
      Paint.Shader := TSkShader.MakeGradientLinear(
        TPointF.Create(0, 0),
        TPointF.Create(W, 0),
        [AC1, AC2]);
      R := TRectF.Create(0.5, 0.5, W - 0.5, H - 0.5);
      ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

      if ABorderColor <> clNone then
      begin
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Stroke;
        Paint.Color := BorderAC;
        Paint.StrokeWidth := ABorderWidth;
        Paint.AntiAlias := True;
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);
      end;
    end);
end;

procedure DrawSkiaGradientRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AColor1, AColor2: TColor;
  ABorderColor: TColor; ABorderWidth: Single);
var
  Bmp: Vcl.Graphics.TBitmap;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(ARect.Width, ARect.Height);
    DrawSkiaGradientRoundRectOnBitmap(Bmp, ARadius, AColor1, AColor2, ABorderColor, ABorderWidth);
    ACanvas.Draw(ARect.Left, ARect.Top, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure DrawSkiaShadowRoundRectOnBitmap(ABitmap: TBitmap;
  const AInnerRect: TRectF; ARadius: Single;
  AShadowColor: TColor; AShadowRadius: Single;
  AOffsetX, AOffsetY: Single);
var
  ShadowAC: TAlphaColor;
begin
  ShadowAC := ColorToAlphaColor(AShadowColor);

  ABitmap.SkiaDraw(
    procedure(const ACanvas: ISkCanvas)
    var
      Paint: ISkPaint;
    begin
      ACanvas.Clear(TAlphaColorRec.Null);

      Paint := TSkPaint.Create;
      Paint.Style := TSkPaintStyle.Fill;
      Paint.Color := TAlphaColor($00000000);  // Transparent - shadow drawn by ImageFilter only
      Paint.AntiAlias := True;
      Paint.ImageFilter := TSkImageFilter.MakeDropShadow(
        AOffsetX, AOffsetY, AShadowRadius, AShadowRadius, ShadowAC);
      ACanvas.DrawRoundRect(AInnerRect, ARadius, ARadius, Paint);
    end);
end;

procedure DrawSkiaShadowRoundRect(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AShadowColor: TColor; AShadowRadius: Single;
  AOffsetX, AOffsetY: Single);
var
  Bmp: Vcl.Graphics.TBitmap;
  Pad: Integer;
  R: TRectF;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;
  Pad := Round(AShadowRadius * 2 + Abs(AOffsetX) + Abs(AOffsetY) + 4);
  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(ARect.Width + Pad * 2, ARect.Height + Pad * 2);
    R := TRectF.Create(Pad, Pad, Pad + ARect.Width, Pad + ARect.Height);
    DrawSkiaShadowRoundRectOnBitmap(Bmp, R, ARadius, AShadowColor, AShadowRadius, AOffsetX, AOffsetY);
    ACanvas.Draw(ARect.Left - Pad, ARect.Top - Pad, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure DrawSkiaRoundRectWithShadow(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  AShadowColor: TColor; AShadowRadius: Single;
  AOffsetX, AOffsetY: Single;
  ABorderColor: TColor; ABorderWidth: Single);
var
  Bmp: Vcl.Graphics.TBitmap;
  Pad: Integer;
  FillAC, BorderAC, ShadowAC: TAlphaColor;
  W, H: Single;
  R: TRectF;
  Paint: ISkPaint;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;
  if (ARect.Width > MAX_SKIA_BITMAP_SIZE) or (ARect.Height > MAX_SKIA_BITMAP_SIZE) then
  begin
    // Fallback: draw directly without bitmap for very large rects
    ACanvas.Brush.Color := AFillColor;
    ACanvas.FillRect(ARect);
    Exit;
  end;
  FillAC := ColorToAlphaColor(AFillColor);
  BorderAC := ColorToAlphaColor(ABorderColor);
  ShadowAC := ColorToAlphaColor(AShadowColor);
  Pad := Round(AShadowRadius * 2 + Abs(AOffsetX) + Abs(AOffsetY) + 4);
  W := ARect.Width;
  H := ARect.Height;

  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(ARect.Width + Pad * 2, ARect.Height + Pad * 2);

    Bmp.SkiaDraw(
      procedure(const ACanvas: ISkCanvas)
      begin
        ACanvas.Clear(TAlphaColorRec.Null);
        R := TRectF.Create(Pad, Pad, Pad + W, Pad + H);

        // Shadow layer
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Fill;
        Paint.Color := TAlphaColor($00000000);  // Transparent - shadow drawn by ImageFilter only
        Paint.AntiAlias := True;
        Paint.ImageFilter := TSkImageFilter.MakeDropShadow(
          AOffsetX, AOffsetY, AShadowRadius, AShadowRadius, ShadowAC);
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

        // Fill layer (on top of shadow)
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Fill;
        Paint.Color := FillAC;
        Paint.AntiAlias := True;
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

        // Border
        if ABorderColor <> clNone then
        begin
          Paint := TSkPaint.Create;
          Paint.Style := TSkPaintStyle.Stroke;
          Paint.Color := BorderAC;
          Paint.StrokeWidth := ABorderWidth;
          Paint.AntiAlias := True;
          ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);
        end;
      end);

    ACanvas.Draw(ARect.Left - Pad, ARect.Top - Pad, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure DrawSkiaGradientRoundRectWithShadow(ACanvas: TCanvas;
  const ARect: TRect; ARadius: Single;
  AColor1, AColor2: TColor;
  AShadowColor: TColor; AShadowRadius: Single;
  AOffsetX, AOffsetY: Single;
  ABorderColor: TColor; ABorderWidth: Single);
var
  Bmp: Vcl.Graphics.TBitmap;
  Pad: Integer;
  AC1, AC2, BorderAC, ShadowAC: TAlphaColor;
  W, H: Single;
  R: TRectF;
  Paint: ISkPaint;
begin
  if (ARect.Width <= 0) or (ARect.Height <= 0) then Exit;
  if (ARect.Width > MAX_SKIA_BITMAP_SIZE) or (ARect.Height > MAX_SKIA_BITMAP_SIZE) then
  begin
    // Fallback: draw directly without bitmap for very large rects
    ACanvas.Brush.Color := AColor1;
    ACanvas.FillRect(ARect);
    Exit;
  end;
  AC1 := ColorToAlphaColor(AColor1);
  AC2 := ColorToAlphaColor(AColor2);
  BorderAC := ColorToAlphaColor(ABorderColor);
  ShadowAC := ColorToAlphaColor(AShadowColor);
  Pad := Round(AShadowRadius * 2 + Abs(AOffsetX) + Abs(AOffsetY) + 4);
  W := ARect.Width;
  H := ARect.Height;

  Bmp := Vcl.Graphics.TBitmap.Create;
  try
    Bmp.SetSize(ARect.Width + Pad * 2, ARect.Height + Pad * 2);

    Bmp.SkiaDraw(
      procedure(const ACanvas: ISkCanvas)
      begin
        ACanvas.Clear(TAlphaColorRec.Null);
        R := TRectF.Create(Pad, Pad, Pad + W, Pad + H);

        // Shadow layer
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Fill;
        Paint.Color := TAlphaColor($00000000);  // Transparent - shadow drawn by ImageFilter only
        Paint.AntiAlias := True;
        Paint.ImageFilter := TSkImageFilter.MakeDropShadow(
          AOffsetX, AOffsetY, AShadowRadius, AShadowRadius, ShadowAC);
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

        // Gradient fill layer
        Paint := TSkPaint.Create;
        Paint.Style := TSkPaintStyle.Fill;
        Paint.AntiAlias := True;
        Paint.Shader := TSkShader.MakeGradientLinear(
          TPointF.Create(Pad, Pad),
          TPointF.Create(Pad + W, Pad),
          [AC1, AC2]);
        ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);

        // Border
        if ABorderColor <> clNone then
        begin
          Paint := TSkPaint.Create;
          Paint.Style := TSkPaintStyle.Stroke;
          Paint.Color := BorderAC;
          Paint.StrokeWidth := ABorderWidth;
          Paint.AntiAlias := True;
          ACanvas.DrawRoundRect(R, ARadius, ARadius, Paint);
        end;
      end);

    ACanvas.Draw(ARect.Left - Pad, ARect.Top - Pad, Bmp);
  finally
    Bmp.Free;
  end;
end;

procedure DrawSkiaRoundRectWithShadowLevel(ACanvas: TCanvas; const ARect: TRect;
  ARadius: Single; AFillColor: TColor;
  AShadowColor: TColor; ALevel: TShadowLevel;
  ABorderColor: TColor; ABorderWidth: Single);
begin
  DrawSkiaRoundRectWithShadow(ACanvas, ARect, ARadius, AFillColor,
    AShadowColor, ALevel.Blur, ALevel.OffsetX, ALevel.OffsetY,
    ABorderColor, ABorderWidth);
end;

end.
