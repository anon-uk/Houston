MIT License

Copyright (c) 2019 Serhiy Mytrovtsiy

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

Stats: https://github.com/exelban/stats
Reference revision: e27b499f42ad5117777a11a3c6b29b7f0f4ae758
The IOKit GPU property-reading approach and disk statistics keys were adapted
from Modules/GPU/reader.swift and Modules/Disk/readers.swift. This app does not
bundle or require the Stats app, its helper, its networking, or its UI.

Mission Center UI adaptations (GPL-3.0-or-later)
Copyright 2023 Romeo Calota
Copyright 2025-2026 Mission Center Developers
https://gitlab.com/mission-center-devs/mission-center
Revision f4109d6ac4d467b3416969d3d17dcdd8c32989c9
The CPU processor-grid algorithm, Performance graph proportions, device
summary card arrangement, color palette, settings labels, and context-menu
structure were adapted into native SwiftUI/AppKit from the UI resources and
src/performance_page/cpu.rs. The application source is supplied under
GPL-3.0-or-later; see LICENSE.

Graph widget (GPL-3.0-or-later)
https://gitlab.com/mission-center-devs/graph-widget
Copyright 2026 Mission Center Developers
The grid sizing, rounded graph frame, optional cubic smoothing, scrolling
behavior, and dashed kernel series were adapted into SwiftUI Canvas from
src/widget.rs and src/render.rs. No GTK or Rust runtime is included.
