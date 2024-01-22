/* -*- Mode: C++; tab-width: 2; indent-tabs-mode: nil; c-basic-offset: 2 -*- */
/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#import <Cocoa/Cocoa.h>

#include "nsColorPicker.h"
#include "nsCocoaUtils.h"
#include "nsThreadUtils.h"

#include "nsCSSValue.h"
#include "nsCSSParser.h"
#include "nsRuleNode.h"

using namespace mozilla;

static unsigned int
HexStrToInt(NSString* str)
{
  unsigned int result = 0;

  for (unsigned int i = 0; i < [str length]; ++i) {
    char c = [str characterAtIndex:i];
    result *= 16;
    if (c >= '0' && c <= '9') {
      result += c - '0';
    } else if (c >= 'A' && c <= 'F') {
      result += 10 + (c - 'A');
    } else {
      result += 10 + (c - 'a');
    }
  }

  return result;
}

@interface NSColorPanelWrapper : NSObject <NSWindowDelegate>
{
  NSColorPanel*  mColorPanel;
  nsColorPicker* mColorPicker;
}
- (id)initWithPicker:(nsColorPicker*)aPicker;
- (void)open:(NSColor*)aInitialColor title:(NSString*)aTitle showsAlpha:(BOOL)aShowsAlpha;
- (void)retarget:(nsColorPicker*)aPicker;
- (void)colorChanged:(NSColorPanel*)aPanel;
@end

@implementation NSColorPanelWrapper
- (id)initWithPicker:(nsColorPicker*)aPicker
{
  mColorPicker = aPicker;
  mColorPanel = [NSColorPanel sharedColorPanel];

  self = [super init];
  return self;
}

- (void)open:(NSColor*)aInitialColor title:(NSString*)aTitle showsAlpha:(BOOL)aShowsAlpha
{
  [mColorPanel setTitle:aTitle];
  [mColorPanel setTarget:self];
  [mColorPanel setShowsAlpha:aShowsAlpha];
  [mColorPanel setDelegate:self];
  [mColorPanel orderFront:nil];
  [mColorPanel setAction:nil];
  [mColorPanel setColor:aInitialColor];
  [mColorPanel setAction:@selector(colorChanged:)];
}

- (void)colorChanged:(NSColorPanel*)aPanel
{
  mColorPicker->Update([mColorPanel color]);
}

- (void)windowWillClose:(NSNotification*)aNotification
{
  mColorPicker->Done();
}

- (void)retarget:(nsColorPicker*)aPicker
{
  mColorPicker->DoneWithRetarget();
  mColorPicker = aPicker;
}

- (void)dealloc
{
  if ([mColorPanel delegate] == self) {
    [mColorPanel setTarget:nil];
    [mColorPanel setAction:nil];
    [mColorPanel setDelegate:nil];
  }

  mColorPanel = nil;
  mColorPicker = nullptr;

  [super dealloc];
}
@end

NS_IMPL_ISUPPORTS(nsColorPicker, nsIColorPicker)

NSColorPanelWrapper* nsColorPicker::sColorPanelWrapper = nullptr;

nsColorPicker::~nsColorPicker()
{
}

NS_IMETHODIMP
nsColorPicker::Init(mozIDOMWindowProxy* aParent, const nsAString& aTitle,
                    const nsAString& aInitialColor, bool aShowAlpha)
{
  MOZ_ASSERT(NS_IsMainThread(),
      "Color pickers can only be opened from main thread currently");
  mTitle = aTitle;
  mColor = aInitialColor;
  mShowsAlpha = aShowAlpha;

  if (sColorPanelWrapper) {
    // Update current wrapper to target the new input instead
    [sColorPanelWrapper retarget:this];
  } else {
    // Create a brand new color panel wrapper
    sColorPanelWrapper = [[NSColorPanelWrapper alloc] initWithPicker:this];
  }
  return NS_OK;
}

/* static */ NSColor*
nsColorPicker::GetNSColorFromHexString(const nsAString& aColor)
{
  nsCSSValue value;
  nsCSSParser parser;
  if (!parser.ParseColorString(aColor, nullptr, 0, value)) {
    return [NSColor colorWithDeviceRed: 0 green: 0 blue: 0 alpha: 1];
  }

  nscolor color;
  if (!nsRuleNode::ComputeColor(value, nullptr, nullptr, color)) {
    return [NSColor colorWithDeviceRed: 0 green: 0 blue: 0 alpha: 1];
  }

  return [NSColor colorWithRed: ((float)NS_GET_R(color))/255.0
                         green: ((float)NS_GET_G(color))/255.0
                          blue: ((float)NS_GET_B(color))/255.0
                         alpha: ((float)NS_GET_A(color))/255.0];
}

/* static */ void
nsColorPicker::GetHexStringFromNSColor(NSColor* aColor, nsAString& aResult)
{
  CGFloat redFloat, greenFloat, blueFloat, alphaFloat;
  [aColor getRed: &redFloat green: &greenFloat blue: &blueFloat alpha: &alphaFloat];
  if (alphaFloat < 1.0f) {
    nsCocoaUtils::GetStringForNSString([NSString stringWithFormat:@"rgba(%d, %d, %d, %1.2f)",
                                         (int)(redFloat * 255 + 0.5f),
                                         (int)(greenFloat * 255 + 0.5f),
                                         (int)(blueFloat * 255 + 0.5f),
                                         (float) alphaFloat],
                                       aResult);
  }
  else {
    nsCocoaUtils::GetStringForNSString([NSString stringWithFormat:@"#%02x%02x%02x",
                                         (int)(redFloat * 255 + 0.5f),
                                         (int)(greenFloat * 255 + 0.5f),
                                         (int)(blueFloat * 255 + 0.5f)],
                                       aResult);
  }
}

NS_IMETHODIMP
nsColorPicker::Open(nsIColorPickerShownCallback* aCallback)
{
  MOZ_ASSERT(aCallback);
  mCallback = aCallback;

  [sColorPanelWrapper open:GetNSColorFromHexString(mColor)
              title:nsCocoaUtils::ToNSString(mTitle)
              showsAlpha:mShowsAlpha];

  NS_ADDREF_THIS();

  return NS_OK;
}

void
nsColorPicker::Update(NSColor* aColor)
{
  NSColor *color = aColor;
  if ([[aColor colorSpaceName] isEqualToString:NSNamedColorSpace])        {
    color = [aColor colorUsingColorSpace:[NSColorSpace genericRGBColorSpace]];
  }

  GetHexStringFromNSColor(color, mColor);
  mCallback->Update(mColor);
}

void
nsColorPicker::DoneWithRetarget()
{
  mCallback->Done(EmptyString());
  mCallback = nullptr;
  NS_RELEASE_THIS();
}

void
nsColorPicker::Done()
{
  [sColorPanelWrapper release];
  sColorPanelWrapper = nullptr;
  DoneWithRetarget();
}
