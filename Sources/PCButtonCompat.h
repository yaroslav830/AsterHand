#pragma once
#import <UIKit/UIKit.h>
#import "PCDesignTokens.h"

typedef NS_ENUM(NSInteger, PCButtonStyle) {
    PCButtonPlain, PCButtonBordered, PCButtonTinted, PCButtonFilled
};

// Keep native configurations on iOS 15+, and use ordinary UIButton properties
// on iOS 14. No selector or class introduced in iOS 15 is sent on the fallback.
static inline void PCStyleButton(UIButton *button, PCButtonStyle kind) {
    if (@available(iOS 15.0, *)) {
        switch(kind) {
            case PCButtonFilled: button.configuration=UIButtonConfiguration.filledButtonConfiguration;break;
            case PCButtonTinted: button.configuration=UIButtonConfiguration.tintedButtonConfiguration;break;
            case PCButtonBordered: button.configuration=UIButtonConfiguration.borderedButtonConfiguration;break;
            default: button.configuration=UIButtonConfiguration.plainButtonConfiguration;break;
        }
        UIButtonConfiguration *style=button.configuration;
        style.baseForegroundColor=kind==PCButtonFilled?PCOnAccentColor():PCTextColor();
        if(kind==PCButtonFilled)style.baseBackgroundColor=PCAccentColor();
        else if(kind!=PCButtonPlain)style.baseBackgroundColor=PCSoftColor();
        style.background.cornerRadius=PCControlRadius;
        button.configuration=style;
    } else {
        button.contentEdgeInsets=UIEdgeInsetsMake(8,12,8,12);
        button.layer.cornerRadius=PCControlRadius;
        if(kind==PCButtonFilled){button.backgroundColor=PCAccentColor();button.tintColor=PCOnAccentColor();[button setTitleColor:button.tintColor forState:UIControlStateNormal];}
        else if(kind!=PCButtonPlain)button.backgroundColor=PCSoftColor();
    }
}
