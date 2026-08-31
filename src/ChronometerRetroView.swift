//
//  ChronometerRetroView.swift
//  TOS Chronometer (Classic) screensaver
//
//  The same panel and mechanism as ChronometerView, built as the original prop
//  rather than the remastered one: dark ink on pale drums behind a white mask,
//  lit by a warm lamp above the opening.
//

import ScreenSaver
import Cocoa

@objc(ChronometerRetroView)
public class ChronometerRetroView: ChronometerView {
    override var readoutFinish: CounterFinish { return .retro }
}
