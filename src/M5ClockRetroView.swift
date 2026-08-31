//
//  M5ClockRetroView.swift
//  M-5 Panel with Retro Clock screensaver
//
//  The same panel and the same mechanism as M5ClockView, built as the original
//  prop instead of the remastered one: dark ink on pale drums behind a white
//  mask, lit by a warm lamp above the opening.
//

import ScreenSaver
import Cocoa

@objc(M5ClockRetroView)
public class M5ClockRetroView: M5ClockView {
    override var readoutFinish: CounterFinish { return .retro }
}
