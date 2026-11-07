import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SwordIcon extends StatelessWidget {
  const SwordIcon({super.key, this.size = 48});

  final double size;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: const CustomPaint(painter: SwordPainter()),
      ),
    );
  }
}

class SwordPainter extends CustomPainter {
  const SwordPainter();

  static const double _pad = 0.05;

  static const double _aEnd = 830;
  static const double _stripEnd = 600;
  static const double _halfSlope = 0.0455;
  static const double _gapStart = 213;
  static const double _gapSlope = 0.0255;
  static const int _steps = 90;

  static const double _lineHalf = 1.25;
  static const double _minLinePx = 0.3;

  static const double _gapCut = 0.4;

  static const List<_Glow> _glows = [
    _Glow(8, 8, 1.4, 0.30),
    _Glow(3.4, 3.2, 0.8, 0.42),
  ];

  static const List<double> _stops = [
    0, 0.10, 0.225, 0.30, 0.42, 0.51, 0.60, 0.65, 0.75, 0.80, 0.84, 0.89, 0.96, 1,
  ];

  static const List<int> _fillRgb = [
    0x7B4FD6, 0x7B4FD6, 0x7B4FD6, 0x8A55B8, 0xD5706C, 0xF1885C, 0xF7A260,
    0xF7AF61, 0xF7B96A, 0xF4C077, 0xF9E1AD, 0xFBF2BD, 0xF9D99C, 0xF6CD88,
  ];
  static const List<double> _fillA = [0.26, 0.38, 0.56, 0.74, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

  static const List<int> _lineRgb = [
    0x9F7FE0, 0xAD8DEA, 0xC79ADB, 0xD9A9DC, 0xF0B8AC, 0xF8CCA4, 0xFAD8A0,
    0xFCE2A8, 0xFEEDB0, 0xFFF2BE, 0xFFF6C4, 0xFFF8D0, 0xFFF0C0, 0xFFEAB4,
  ];
  static const List<double> _lineA = [0.65, 0.80, 0.90, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1];

  static const double _r2 = 0.7071067811865476;

  static const Offset _gdCenter = Offset(374, 628);
  static const double _gdR = 59;

  static const double _haloBase = 73.5;
  static const double _haloAmp = 5;
  static const double _haloAng = 290;
  static const int _haloSteps = 96;

  static const List<_Glow> _haloGlows = [
    _Glow(1.8, 7, 1.5, 0.30),
    _Glow(1.3, 2.6, 0.8, 0.45),
  ];

  static const List<double> _haloStops = [0, 0.74, 0.86, 1];
  static const List<int> _haloRgb = [0xFFFDEB, 0xFFFDEB, 0xFFF4C4, 0xFFE9A4];
  static const int _haloGlowRgb = 0xFFE9A8;

  static const Offset _slCenter = Offset(372, 630);
  static const double _slHalfLen = 105;
  static const double _slHalf = 4.5;
  static const double _slTaperStart = 62;
  static const double _slTaperPow = 0.6;
  static const int _slSteps = 48;

  static const List<_Glow> _slGlows = [
    _Glow(1.7, 2.2, 0.6, 0.18),
  ];

  static const List<double> _slStops = [
    0, 0.176, 0.324, 0.41, 0.47, 0.5, 0.53, 0.59, 0.676, 0.824, 1,
  ];
  static const List<int> _slRgb = [
    0xEBC878, 0xF0D58E, 0xFAF0BC, 0xFEFDC8, 0xFFFDF2, 0xFFFEF6,
    0xFFFDF2, 0xFEFDC8, 0xFAF0BC, 0xF0D58E, 0xEBC878,
  ];

  static const Offset _swCenter = Offset(373, 629);

  static const int _swPer = 8;
  static const double _swGap = 0;
  static const double _swCore = 0.3;
  static const double _swLineFrac = 0.25;

  static const List<_Glow> _swGlows = [
    _Glow(1.2, 8, 1.4, 0.30),
    _Glow(1.0, 3.2, 0.8, 0.42),
  ];

  static const List<List<double>> _swWisp = [
    [262, 486, 10], [290, 486, 10], [320, 489, 8.5], [350, 491, 6.5],
    [380, 489, 5.8], [410, 481, 5], [435, 470, 4.2], [458, 455, 3.3],
    [476, 440, 2.2], [488, 427, 0],
  ];

  static const List<List<double>> _swLoop = [
    [262, 486, 10], [225, 496, 9.7], [199, 515, 9.8], [178, 538, 10.5],
    [163, 566, 11.2], [154, 596, 12.2], [151, 625, 13.5], [155, 656, 14.8],
    [166, 686, 15], [183, 711, 13.5], [206, 730, 9], [226, 742, 4.5],
    [238, 752, 0], [254, 772, 0], [266, 785, 4], [285, 810, 10],
    [313, 834, 14.5], [346, 847, 15.5], [381, 849, 13.4], [417, 843, 11.6],
    [450, 829, 10.5], [479, 808, 9.9], [502, 780, 9.5], [515, 746, 9.8],
    [518, 712, 10],
  ];

  static const List<List<double>> _swRight = [
    [518, 712, 10], [517, 690, 9], [512, 665, 7.8], [511, 640, 6.8],
    [515, 615, 6.2], [522, 590, 5.6], [533, 565, 5], [547, 541, 4.2],
    [562, 522, 3], [575, 509, 0],
  ];

  static const List<List<double>> _swLens = [
    [182, 507, 0], [205, 487, 3.5], [232, 473, 5], [262, 466, 5.8],
    [292, 466, 5.5], [322, 470, 3.5], [352, 476, 0],
  ];

  static const List<double> _swAng = [
    0, 16, 24, 29, 35, 41, 46, 51, 57, 63, 73, 78,
    83, 88, 94, 99, 104, 109, 114, 126, 143, 150, 159, 165,
    170, 175, 180, 186, 192, 198, 206, 214, 222, 229, 236, 242,
    248, 255, 262, 270, 285, 300, 329, 340, 350, 360,
  ];

  static const List<int> _swFill = [
    0x8A5BCF, 0x9A62B8, 0xC9757A, 0xE8855A, 0xF09A5E, 0xF6B864, 0xF7CF7E, 0xFBDB98,
    0xFCE3A8, 0xFFF0C4, 0xFFF2CC, 0xFBE0A0, 0xF6CF84, 0xF5BE78, 0xF3A768, 0xEE9660,
    0xD97B6E, 0xB96E92, 0x8A5BC4, 0x7B4FD6, 0x7B4FD6, 0x8D65C0, 0x9D65A8, 0xBA7A7C,
    0xDE8B68, 0xF1A468, 0xF0B674, 0xF1CE8B, 0xF6E2A8, 0xFAEABE, 0xFBF1D1, 0xF9E2AD,
    0xF6CE84, 0xF2BC7A, 0xF2906B, 0xE77F68, 0xC67880, 0xAE74A8, 0x9068B4, 0x8260B0,
    0x7B4FD6, 0x7B4FD6, 0x7B4FD6, 0x7F52D2, 0x8456D0, 0x8A5BCF,
  ];

  static const List<int> _swLine = [
    0xC8A0E6, 0xDCB1E5, 0xF9BAB7, 0xF6BD9A, 0xFFDDA7, 0xFFE2A5, 0xFFFDD0, 0xFFFDD0,
    0xFFFCDE, 0xFFFDF1, 0xFFFDF1, 0xFDEDC4, 0xFBECB5, 0xFFE7A6, 0xFBDFA9, 0xFDCA9B,
    0xDB9DB5, 0xC8A0E6, 0xC8A0E6, 0xB48FE0, 0xB48FE0, 0xC09AD8, 0xE2B0CC, 0xE3A09C,
    0xF2B090, 0xF8D19A, 0xFCF0AE, 0xFDF5C8, 0xFDF8DA, 0xFEFDEF, 0xFFFCE0, 0xFFF5C0,
    0xFFF3C2, 0xFDE3AD, 0xFAD09A, 0xF9B98B, 0xE6A0B0, 0xCE9DD0, 0xBF97D5, 0xB08FD0,
    0xA585CC, 0xA98BEA, 0x9D7DE0, 0x9D80D4, 0xAC8EDC, 0xC8A0E6,
  ];

  static const double _k2 = 1.4142135623730951;

  static const List<List<double>> _bandPts = [
    [562.6, 411.1, 8.72], [533.3, 438.4, 9.12], [487, 477, 9.7], [470, 492, 9.4],
    [440, 514, 9.2], [400, 536, 8.2], [360, 547, 7.6], [330, 548, 7], [300, 540, 5.5],
    [278, 527, 3.2], [256, 514, 0],
  ];

  static const List<List<double>> _wedgePts = [
    [588.9, 437.4, 8.72], [561.6, 466.7, 9.12], [523, 513, 9.7], [512, 528, 10],
    [500, 555, 11.5], [484, 590, 12], [470, 625, 13.5], [466, 655, 14.5], [470, 690, 14],
    [480, 722, 9], [488, 750, 0],
  ];

  static const List<_Deco> _dcBody = [
    _Deco([[332, 586, 4], [312, 606, 9], [293, 632, 12.5], [284, 665, 12.5], [280, 700, 11], [272, 730, 6], [266, 746, 0]], 0.07, Offset(332, 586), Offset(266, 746), [0, 0.18, 0.4, 0.62, 0.85, 1], [0x7B4FD6, 0x9A62B8, 0xE8855A, 0xF3A768, 0xF8D596, 0xFFF0B8]),
    _Deco([[268, 744, 0], [290, 730, 6], [320, 716, 11], [360, 708, 11], [400, 700, 9], [428, 690, 4]], 0.07, Offset(268, 744), Offset(428, 690), [0, 0.2, 0.4, 0.62, 0.82, 1], [0xFFF0B8, 0xF9D08A, 0xF2A064, 0xE0807A, 0xB06EA8, 0x7B4FD6]),
    _Deco([[287, 557, 0], [293, 570, 4], [297, 583, 0]], 0, Offset(287, 557), Offset(297, 583), [0, 1], [0x7B4FD6, 0x6B46BE]),
  ];

  static const List<_Deco> _dcHook = [
    _Deco([[246.6, 670, 0], [242, 690, 4], [240, 715, 7], [241, 735, 7], [250, 753, 6.5], [265, 762, 6], [290, 762, 4], [311, 759, 2], [333, 756, 0]], 0, Offset(246.6, 670), Offset(333, 756), [0, 0.5, 1], [0xFBEDB0, 0xFFF6C8, 0xFBE9A8]),
  ];

  static const List<_Deco> _dcFlecks = [
    _Deco([[106, 567, 0], [99, 595, 5], [96, 620, 6], [98, 642, 3.5], [101, 655, 0]], 0, Offset(106, 567), Offset(101, 655), [0, 0.3, 1], [0xF6DE94, 0xEF8A48, 0xEF7A3C]),
    _Deco([[118, 647, 0], [116, 665, 4], [122, 685, 4.5], [132, 700, 2.5], [139, 705, 0]], 0, Offset(118, 647), Offset(139, 705), [0, 0.5, 1], [0xFFF1B5, 0xF6C07A, 0xEF8A48]),
    _Deco([[135, 712, 0], [143, 718, 3], [152, 727, 0]], 0, Offset(135, 712), Offset(152, 727), [0, 1], [0xEE7B3C, 0xEE7B3C]),
    _Deco([[256, 564, 0], [246, 575, 4.5], [241, 590, 4], [242, 607, 0]], 0, Offset(256, 564), Offset(242, 607), [0, 1], [0xF28040, 0xEE7438]),
    _Deco([[274, 640, 0], [273, 655, 4.5], [270, 675, 5.5], [267, 695, 3.5], [267, 709, 0]], 0, Offset(274, 640), Offset(267, 709), [0, 1], [0xF28040, 0xEE7438]),
    _Deco([[269, 511, 0], [274.5, 511, 3], [280, 511.5, 0]], 0, Offset(269, 511), Offset(280, 511.5), [0, 1], [0xFFF3BE, 0xFBE8A0]),
    _Deco([[294, 524, 0], [301, 523.5, 3.8], [308, 523, 0]], 0, Offset(294, 524), Offset(308, 523), [0, 1], [0xEE7B3C, 0xEE7B3C]),
    _Deco([[386, 517, 0], [395, 516, 3.2], [404, 515, 0]], 0, Offset(386, 517), Offset(404, 515), [0, 1], [0xFFF3BE, 0xFBE8A0]),
    _Deco([[269, 418, 0], [280, 413, 3], [292, 413, 4], [303, 418, 2], [308, 423, 0]], 0, Offset(269, 418), Offset(308, 423), [0, 1], [0xFFF3BE, 0xFBE8A0]),
    _Deco([[333, 477, 0], [342.5, 476, 2.6], [352, 477, 0]], 0, Offset(333, 477), Offset(352, 477), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[307, 676, 0], [305, 686, 1.4], [303, 696, 0]], 0, Offset(307, 676), Offset(303, 696), [0, 1], [0xF08A62, 0xF08A62]),
    _Deco([[303, 696, 0], [313, 695, 1.6], [324, 694, 0]], 0, Offset(303, 696), Offset(324, 694), [0, 1], [0xF08A62, 0xF08A62]),
    _Deco([[300, 729, 0], [308, 729, 3], [316, 729, 0]], 0, Offset(300, 729), Offset(316, 729), [0, 1], [0xEE7B3C, 0xEE7B3C]),
    _Deco([[374, 723, 0], [379, 723, 2.5], [384, 722, 0]], 0, Offset(374, 723), Offset(384, 722), [0, 1], [0xEE8A4C, 0xEE8A4C]),
    _Deco([[396, 720, 0], [410, 716, 3], [430, 711, 3], [447, 708, 0]], 0, Offset(396, 720), Offset(447, 708), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[511, 557, 0], [504.5, 565, 2.6], [498, 573, 0]], 0, Offset(511, 557), Offset(498, 573), [0, 1], [0xF7C482, 0xF7C482]),
    _Deco([[491, 586, 0], [487, 600, 4.5], [484, 620, 4], [483, 628, 0]], 0, Offset(491, 586), Offset(483, 628), [0, 1], [0xF3B060, 0xF3A455]),
    _Deco([[487, 632, 0], [485, 640, 3], [483, 648, 0]], 0, Offset(487, 632), Offset(483, 648), [0, 1], [0xFBE9A0, 0xFBE9A0]),
    _Deco([[477, 692, 0], [483, 705, 4.5], [490, 722, 0]], 0, Offset(477, 692), Offset(490, 722), [0, 1], [0xF2A455, 0xF29A4C]),
    _Deco([[578, 604, 0], [586, 614, 3], [592, 626, 4.5], [594, 638, 4.5], [592, 646, 2]], 0, Offset(578, 604), Offset(592, 646), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[590, 654, 0], [590, 660, 3], [590, 666, 0]], 0, Offset(590, 654), Offset(590, 666), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[544, 689, 0], [543, 698, 3.2], [541, 708, 0]], 0, Offset(544, 689), Offset(541, 708), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[551, 727, 0], [551, 738, 3.2], [547, 750, 3.2], [541, 759, 0]], 0, Offset(551, 727), Offset(541, 759), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[594, 741, 0], [590, 760, 5], [580, 785, 8], [568, 804, 8], [558, 818, 3]], 0, Offset(594, 741), Offset(558, 818), [0, 1], [0x7B4FD6, 0x6B46BE]),
    _Deco([[288, 840, 0], [294, 845, 3], [300, 852, 0]], 0, Offset(288, 840), Offset(300, 852), [0, 1], [0xEE7B3C, 0xEE7B3C]),
    _Deco([[310, 857, 0], [325, 865, 3], [345, 872, 5.5], [362, 872, 4.5], [379, 866, 0]], 0, Offset(310, 857), Offset(379, 866), [0, 0.5, 1], [0xEE7B3C, 0xF5A860, 0xFBE29A]),
    _Deco([[391, 870, 0], [398.5, 868, 3.2], [406, 866, 0]], 0, Offset(391, 870), Offset(406, 866), [0, 1], [0xFFF3B8, 0xFFF3B8]),
  ];

  static const List<int> _hcCol = [0xA81810, 0xCF2A1B, 0xE23B26, 0xCB2518, 0xA81810];
  static const List<double> _hcStops = [0, 0.2, 0.5, 0.82, 1];

  static const double _gripQ0 = 335;
  static const double _gripQ1 = 575;
  static const double _gripH0 = 11.5;
  static const double _gripH1 = 9.5;
  static const double _gripR = 5;

  static const List<List<double>> _hsLight = [
    [352, -8, 376, -4, 1.3], [372, -8.5, 394, -7.5, 1.6], [404, -7.5, 430, -3, 1.3],
    [452, -4.5, 497, -2.2, 1.5], [470, 4.5, 523, 1.5, 1.3], [512, -8.5, 538, -5, 1.2],
    [546, -4, 566, -1.5, 1.2], [548, 3.5, 565, 1.5, 1.1],
  ];

  static const List<List<double>> _hsOrange = [
    [362, -1.5, 392, 7.5, 4.2], [418, 0, 444, 7.5, 2.8], [486, -1, 516, 6, 2.4],
  ];

  static const List<List<double>> _pmRing = [
    [79.8, 902, 0], [70, 899.3, 2], [59, 898.7, 3.6], [48, 900.4, 4], [37, 907, 4.2],
    [28.2, 916.9, 4.2], [23.2, 929, 4.2], [22.1, 940, 4.2], [24.3, 953, 4.2],
    [31.5, 965.2, 4.2], [42.5, 974, 4.2], [56.8, 977.9, 4.2], [70, 977.3, 4.2],
    [83, 972.9, 4.2], [94, 964, 4.2], [101.8, 953, 4], [104, 940, 3.6],
    [102.9, 929, 3], [103.5, 923, 0],
  ];

  static const List<List<double>> _pmInner = [
    [51.3, 902.6, 0], [35.9, 913.6, 3.2], [31.5, 929, 3.6], [31.5, 942, 3.6],
    [35.9, 956.4, 3.6], [46.9, 966.3, 3.4], [61, 969.6, 3.2], [73.2, 966.9, 2.2],
    [76, 963.2, 0],
  ];

  static const List<List<double>> _pmTail = [
    [16, 936.6, 0], [19.4, 952, 3.5], [26, 966.3, 3.8], [37, 979.5, 3.6],
    [51.3, 986.6, 2.8], [56.8, 988.8, 1.5],
  ];

  static const double _pmThin = 0.74;

  static const List<List<double>> _pmOuter = [
    [66, 894, 0], [48, 893, 1.6], [32, 901, 2], [19, 916, 2.2], [12, 935, 2.2],
    [13, 955, 1.8], [20, 972, 1.2], [28, 983, 0],
  ];

  static const List<List<double>> _pmTailLens = [
    [47, 990, 0], [57, 989, 2.6], [67, 988.5, 0],
  ];

  static const List<List<double>> _pmNavyA = [
    [51.5, 917, 0], [59, 913, 2.6], [66.6, 909.2, 0],
  ];

  static const List<List<double>> _pmNavyB = [
    [84.5, 951, 0], [90.6, 942, 2.8], [96.5, 932, 0],
  ];

  static const double _gemQ = 620;
  static const double _gemP = 1;

  static const List<List<double>> _gemPts = [
    [577, 1], [590, -4.5], [604, -9.5], [622, -11], [640, -8.5], [651, -3.5], [655, 1],
    [651, 5.5], [640, 10.5], [622, 13], [604, 11.5], [590, 6.5],
  ];

  static const List<List<double>> _spkDots = [
    [206.6, 771.9, 3.4], [194.1, 791.3, 3.7], [180.7, 787.6, 2.4], [206.6, 808.4, 2.9],
    [228.3, 807.9, 2.1], [210.7, 820.8, 3.4], [125, 850.3, 4], [117.6, 866.4, 3.2],
    [138, 892, 4.3], [125.6, 896.6, 2.3], [226.3, 786.4, 1.2],
  ];

  static const List<List<double>> _spkOvals = [
    [234.4, 792.3, 6, 4, -30], [141.7, 879.2, 5.4, 4.4, -20],
  ];

  static const List<List<double>> _spkTiny = [
    [203.5, 780.9, 1.1], [125, 838.9, 1], [132, 843, 0.9], [101.5, 868.5, 1],
    [163.9, 874.2, 1], [151, 881.6, 0.9], [132, 907, 1.2], [228.5, 813.5, 1],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final g = _Grid(size, _pad);
    _paintAmbient(canvas, g);
    _paintSwirls(canvas, g);
    _paintGuard(canvas, g);
    _paintSlash(canvas, g);
    _paintLensing(canvas, g);
    _paintBlade(canvas, g);
    _paintFlecks(canvas, g);
    _paintHandle(canvas, g);
    _paintPommel(canvas, g);
    _paintSparkles(canvas, g);
  }

  @override
  bool shouldRepaint(covariant SwordPainter oldDelegate) => false;

  void _paintAmbient(Canvas canvas, _Grid g) {
    final guard = g.p(_gdCenter);
    final guardR = 340 * g.s;
    canvas.drawCircle(
      guard,
      guardR,
      Paint()
        ..shader = ui.Gradient.radial(
          guard,
          guardR,
          [
            _rgba(0xFFB767, 0.2),
            _rgba(0xC08A8E, 0.1),
            _rgba(0x7B4FD6, 0.05),
            _rgba(0x7B4FD6, 0),
          ],
          [0, 0.38, 0.7, 1],
        ),
    );

    final from = g.p(const Offset(1000, 0));
    final to = g.p(const Offset(430, 570));
    canvas.drawLine(
      from,
      to,
      Paint()
        ..strokeWidth = 70 * g.s
        ..strokeCap = StrokeCap.round
        ..shader = ui.Gradient.linear(
          from,
          to,
          [_rgba(0xB391F0, 0), _rgba(0xB391F0, 0.1), _rgba(0xF6B36B, 0.18)],
          [0, 0.45, 1],
        )
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(26 * g.s, 1.5)),
    );

    final pommel = g.p(const Offset(62, 944));
    final pommelR = 105 * g.s;
    canvas.drawCircle(
      pommel,
      pommelR,
      Paint()
        ..shader = ui.Gradient.radial(
          pommel,
          pommelR,
          [_rgba(0xFFE08A, 0.22), _rgba(0xA07AE6, 0.08), _rgba(0xA07AE6, 0)],
          [0, 0.5, 1],
        ),
    );
  }

  void _paintLensing(Canvas canvas, _Grid g) {
    for (final d in _dcBody) {
      _drawDeco(canvas, g, d);
    }
  }

  void _paintFlecks(Canvas canvas, _Grid g) {
    for (final d in _dcFlecks) {
      _drawDeco(canvas, g, d);
    }
  }

  void _drawDeco(Canvas canvas, _Grid g, _Deco d) {
    final from = g.p(d.from);
    final to = g.p(d.to);
    _drawSwirl(
      canvas,
      g,
      _swRuns(d.pts, g),
      d.gap,
      ui.Gradient.linear(from, to, [for (final v in d.fill) _rgba(v, 1)], d.stops),
      (a) => ui.Gradient.linear(
        from,
        to,
        [for (final v in d.fill) _rgba(_decoLine(v), a)],
        d.stops,
      ),
    );
  }

  static int _decoLine(int v) {
    int m(int c) => (c * 0.45 + 255 * 0.55).round();
    return (m((v >> 16) & 0xFF) << 16) | (m((v >> 8) & 0xFF) << 8) | m(v & 0xFF);
  }

  Offset _hp(_Grid g, double q, double p) => g.p(
        Offset((1002.5 + _k2 * (p - q)) / 2, (1002.5 + _k2 * (p + q)) / 2),
      );

  Path _hLocal(_Grid g, Path local) {
    final k = g.s * _r2;
    final o = g.p(const Offset(501.25, 501.25));
    final m = Matrix4(-k, k, 0, 0, k, k, 0, 0, 0, 0, 1, 0, o.dx, o.dy, 0, 1);
    return local.transform(m.storage);
  }

  Path _lensPath(Offset a, Offset b, double w) {
    final d = b - a;
    final len = d.distance;
    final nr = Offset(d.dy / len, -d.dx / len);
    final c = <Offset>[];
    final n = <Offset>[];
    final hw = <double>[];
    for (var i = 0; i <= 12; i++) {
      final t = i / 12;
      c.add(a + d * t);
      n.add(nr);
      hw.add(w * math.sin(math.pi * t));
    }
    return _ribbon(c, n, hw);
  }

  void _blob(Canvas canvas, _Grid g, double x, double y, double r, double alpha, double sigma) {
    canvas.drawCircle(
      g.p(Offset(x, y)),
      r * g.s,
      Paint()
        ..color = Color.fromRGBO(255, 255, 255, alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(sigma * g.s, 0.6)),
    );
  }

  Path _gripLocal() {
    const r = _gripR;
    return Path()
      ..moveTo(_gripQ0 + r, -_gripH0)
      ..lineTo(_gripQ1 - r, -_gripH1)
      ..quadraticBezierTo(_gripQ1, -_gripH1, _gripQ1, -_gripH1 + r)
      ..lineTo(_gripQ1, _gripH1 - r)
      ..quadraticBezierTo(_gripQ1, _gripH1, _gripQ1 - r, _gripH1)
      ..lineTo(_gripQ0 + r, _gripH0)
      ..quadraticBezierTo(_gripQ0, _gripH0, _gripQ0, _gripH0 - r)
      ..lineTo(_gripQ0, -_gripH0 + r)
      ..quadraticBezierTo(_gripQ0, -_gripH0, _gripQ0 + r, -_gripH0)
      ..close();
  }

  void _paintHandle(Canvas canvas, _Grid g) {
    const mid = (_gripQ0 + _gripQ1) / 2;
    const hw = (_gripH0 + _gripH1) / 2;
    final grip = _hLocal(g, _gripLocal());

    canvas.drawPath(
      _hLocal(
        g,
        Path()..addRRect(RRect.fromLTRBR(330, -16, 600, 16, const Radius.circular(16))),
      ),
      Paint()
        ..color = const Color.fromRGBO(255, 255, 255, 0.2)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(9 * g.s, 1.5)),
    );

    canvas.drawPath(
      grip,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(
          _hp(g, mid, -hw),
          _hp(g, mid, hw),
          [for (final v in _hcCol) _rgba(v, 1)],
          _hcStops,
        ),
    );
    canvas.drawPath(
      grip,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.0 * g.s, 0.5)
        ..color = const Color(0xFF9E1710),
    );

    for (final s in _hsLight) {
      canvas.drawPath(
        _lensPath(_hp(g, s[0], s[1]), _hp(g, s[2], s[3]), s[4] * g.s),
        Paint()
          ..color = const Color(0xFFF9B49A)
          ..isAntiAlias = true,
      );
    }
    for (final s in _hsOrange) {
      canvas.drawPath(
        _lensPath(_hp(g, s[0], s[1]), _hp(g, s[2], s[3]), s[4] * g.s),
        Paint()
          ..color = const Color(0xFFF59A62)
          ..isAntiAlias = true,
      );
    }

    for (final d in _dcHook) {
      _drawDeco(canvas, g, d);
    }
  }

  Path _gemPath(_Grid g, double k) {
    final path = Path();
    for (var i = 0; i < _gemPts.length; i++) {
      final q = _gemQ + (_gemPts[i][0] - _gemQ) * k;
      final p = _gemP + (_gemPts[i][1] - _gemP) * k;
      if (i == 0) {
        path.moveTo(q, p);
      } else {
        path.lineTo(q, p);
      }
    }
    path.close();
    return _hLocal(g, path);
  }

  List<List<double>> _thin(List<List<double>> pts) => [
        for (final p in pts) [p[0], p[1], p[2] * _pmThin],
      ];

  void _paintPommel(Canvas canvas, _Grid g) {
    final lilac = _solid(0x8F6FD9, 1);
    ui.Shader lilacLine(double a) => _solid(0xC9B5F7, a);
    final navy = Paint()..color = const Color(0xFF25097A);

    for (final pts in const [_pmOuter, _pmRing, _pmInner, _pmTail]) {
      final runs = _swRuns(_thin(pts), g);
      _drawSwirl(canvas, g, runs, 0, lilac, lilacLine);
      canvas.drawPath(_swPath(runs, (h) => 0.0, (h) => h * 0.42), navy);
    }

    final tailLens = _swRuns(_thin(_pmTailLens), g);
    _drawSwirl(canvas, g, tailLens, 0, lilac, lilacLine);
    canvas.drawPath(_swPath(tailLens, (h) => 0.0, (h) => h * 0.42), navy);

    for (final pts in const [_pmNavyA, _pmNavyB]) {
      _drawSwirl(canvas, g, _swRuns(pts, g), 0, _solid(0x2C0C86, 1), lilacLine);
    }

    final gem = _gemPath(g, 1);
    final tip = _hp(g, _gemPts.first[0], _gemP);
    final base = _hp(g, _gemPts[6][0], _gemP);
    final center = _hp(g, _gemQ, _gemP);

    canvas.drawPath(
      _gemPath(g, 1.18),
      Paint()
        ..color = const Color.fromRGBO(255, 214, 92, 0.6)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(5 * g.s, 0.9)),
    );
    canvas.drawPath(
      gem,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(
          tip,
          base,
          const [Color(0xFFFFFAD6), Color(0xFFFFE98C), Color(0xFFF6C655)],
          [0, 0.5, 1],
        ),
    );
    canvas.drawPath(_gemPath(g, 0.62), Paint()..color = const Color(0xE6FFFBE4));
    canvas.drawPath(
      gem,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.5 * g.s, 0.5)
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFF4B8),
    );

    canvas.save();
    canvas.clipPath(gem);
    canvas.drawCircle(
      center,
      11 * g.s,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(3.5 * g.s, 0.8)),
    );
    canvas.restore();
    canvas.drawPath(
      _gemPath(g, 0.4),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.8 * g.s, 0.4)),
    );

    final neck = _hp(g, _gripQ1, 0);
    canvas.drawCircle(
      neck,
      9 * g.s,
      Paint()
        ..color = const Color.fromRGBO(255, 255, 255, 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(3 * g.s, 0.8)),
    );
    canvas.drawCircle(
      neck,
      5.2 * g.s,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.9 * g.s, 0.4)),
    );
  }

  void _star(Canvas canvas, _Grid g, double x, double y, double r) {
    final c = g.p(Offset(x, y));
    for (var k = 0; k < 4; k++) {
      final ang = math.pi * k / 4;
      final len = (k.isEven ? r : r * 0.6) * g.s;
      final d = Offset(math.cos(ang), math.sin(ang)) * len;
      canvas.drawPath(
        _lensPath(c - d, c + d, len * 0.13),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.6 * g.s, 0.3)),
      );
    }
  }

  void _paintSparkles(Canvas canvas, _Grid g) {
    _blob(canvas, g, 205, 797, 13, 0.5, 6);
    _blob(canvas, g, 127, 873, 11, 0.6, 5);
    _star(canvas, g, 205, 797, 26);
    _star(canvas, g, 127, 873, 22);

    canvas.drawPath(
      _lensPath(g.p(const Offset(222, 781)), g.p(const Offset(200, 803)), 3.6 * g.s),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.2 * g.s, 0.5)),
    );

    for (final d in _spkDots) {
      _blob(canvas, g, d[0], d[1], d[2] * 1.8, 0.32, d[2] * 0.7);
      canvas.drawCircle(
        g.p(Offset(d[0], d[1])),
        math.max(d[2] * g.s, 0.4),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..isAntiAlias = true,
      );
    }

    for (final e in _spkOvals) {
      final c = g.p(Offset(e[0], e[1]));
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(e[4] * math.pi / 180);
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: e[2] * 2 * g.s, height: e[3] * 2 * g.s),
        Paint()
          ..color = const Color(0xFFFFFFFF)
          ..isAntiAlias = true,
      );
      canvas.restore();
    }

    for (final d in _spkTiny) {
      canvas.drawCircle(
        g.p(Offset(d[0], d[1])),
        math.max(d[2] * g.s, 0.3),
        Paint()..color = const Color.fromRGBO(216, 210, 210, 0.8),
      );
    }
  }

  void _paintGuard(Canvas canvas, _Grid g) {
    final c = g.p(_gdCenter);
    final r = _gdR * g.s;

    Path haloPath(double mul) {
      final path = Path();
      for (var i = 0; i < _haloSteps; i++) {
        final deg = 360 * i / _haloSteps;
        final out = _gdR + (_haloOuter(deg) - _gdR) * mul;
        final a = deg * math.pi / 180;
        final p = c + Offset(math.cos(a), math.sin(a)) * (out * g.s);
        if (i == 0) {
          path.moveTo(p.dx, p.dy);
        } else {
          path.lineTo(p.dx, p.dy);
        }
      }
      path.close();
      return path;
    }

    for (final glow in _haloGlows) {
      canvas.drawPath(
        haloPath(glow.mul),
        Paint()
          ..color = _rgba(_haloGlowRgb, glow.alpha)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(glow.sigma * g.s, glow.minSigmaPx),
          ),
      );
    }

    canvas.drawPath(
      haloPath(1),
      Paint()
        ..shader = ui.Gradient.radial(
          c,
          80 * g.s,
          [for (final v in _haloRgb) _rgba(v, 1)],
          _haloStops,
        ),
    );

    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = const Color(0xFF000000)
        ..isAntiAlias = true,
    );
  }

  double _haloOuter(double deg) =>
      _haloBase + _haloAmp * math.cos((deg - _haloAng) * math.pi / 180);

  void _paintSlash(Canvas canvas, _Grid g) {
    const dir = Offset(_r2, _r2);
    const nrm = Offset(_r2, -_r2);
    final half = math.max(_slHalf * g.s, _minLinePx);

    final c = <Offset>[];
    final n = <Offset>[];
    final hw = <double>[];
    for (var i = 0; i <= _slSteps; i++) {
      final t = -_slHalfLen + 2 * _slHalfLen * i / _slSteps;
      final u = math.min(
        1.0,
        math.max(0.0, (t.abs() - _slTaperStart) / (_slHalfLen - _slTaperStart)),
      );
      c.add(g.p(_slCenter + dir * t));
      n.add(nrm);
      hw.add(half * math.pow(1 - u, _slTaperPow));
    }

    for (final glow in _slGlows) {
      final gh = [for (final w in hw) w * glow.mul];
      canvas.drawPath(
        _ribbon(c, n, gh),
        Paint()
          ..color = _rgba(_haloGlowRgb, glow.alpha)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(glow.sigma * g.s, glow.minSigmaPx),
          ),
      );
    }

    canvas.drawPath(
      _ribbon(c, n, hw),
      Paint()
        ..shader = ui.Gradient.linear(
          g.p(_slCenter - dir * _slHalfLen),
          g.p(_slCenter + dir * _slHalfLen),
          [for (final v in _slRgb) _rgba(v, 1)],
          _slStops,
        ),
    );
  }

  void _paintBlade(Canvas canvas, _Grid g) {
    final up = _strip(g, -1);
    final lo = _strip(g, 1);

    final from = g.p(const Offset(1000, 0));
    final to = g.p(const Offset(1000 - _aEnd * _r2, _aEnd * _r2));
    final fillShader = ui.Gradient.linear(from, to, _ramp(_fillRgb, _fillA), _stops);
    final lineShader = ui.Gradient.linear(from, to, _ramp(_lineRgb, _lineA), _stops);

    Path lines(double mul) => Path()
      ..addPath(_edgeLine(up, g, -1, true, mul), Offset.zero)
      ..addPath(_edgeLine(lo, g, 1, true, mul), Offset.zero)
      ..addPath(_edgeLine(up, g, -1, false, mul), Offset.zero)
      ..addPath(_edgeLine(lo, g, 1, false, mul), Offset.zero);

    canvas.saveLayer(g.bounds, Paint());
    for (final glow in _glows) {
      final shader = ui.Gradient.linear(
        from,
        to,
        _ramp(_lineRgb, _lineA, glow.alpha),
        _stops,
      );
      canvas.drawPath(
        lines(glow.mul),
        Paint()
          ..shader = shader
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(glow.sigma * g.s, glow.minSigmaPx),
          ),
      );
    }
    if (_gapCut > 0) {
      canvas.drawPath(
        _gapPath(up, lo),
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(0, 0, 0, _gapCut)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5 * g.s, 0.5)),
      );
    }
    canvas.restore();

    final fill = Path()
      ..addPath(_ribbon(up.center, up.nrm, up.half), Offset.zero)
      ..addPath(_ribbon(lo.center, lo.nrm, lo.half), Offset.zero);
    canvas.drawPath(fill, Paint()..shader = fillShader);

    canvas.drawPath(lines(1), Paint()..shader = lineShader);
  }

  _Strip _strip(_Grid g, int side) {
    final c = <Offset>[];
    final hw = <double>[];
    final dist = <double>[];
    for (var i = 0; i <= _steps; i++) {
      final a = _stripEnd * i / _steps;
      final h = _halfSlope * a;

      final overlap = 0.6 * math.min(1.0, a / 60);
      final hg = math.max(-overlap, _gapSlope * (a - _gapStart));
      final o = side * (h + hg) / 2;

      c.add(g.p(Offset(1000 - (a - o) * _r2, (a + o) * _r2)));
      hw.add((h - hg) / 2 * g.s);
      dist.add(a);
    }

    final flare = _swCurve(side < 0 ? _bandPts : _wedgePts, g);
    var run = _stripEnd;
    for (var i = 1; i < flare.c.length; i++) {
      run += (flare.c[i] - flare.c[i - 1]).distance / g.s;
      c.add(flare.c[i]);
      hw.add(flare.h[i]);
      dist.add(run);
    }

    final n = <Offset>[];
    for (var i = 0; i < c.length; i++) {
      final t = c[math.min(c.length - 1, i + 1)] - c[math.max(0, i - 1)];
      final len = t.distance;
      n.add(Offset(t.dy / len, -t.dx / len));
    }
    return _Strip(c, n, hw, dist);
  }

  Path _edgeLine(_Strip s, _Grid g, int side, bool outer, double mul) {
    final k0 = outer ? 0 : _gapIndex(s);
    final c = <Offset>[];
    final nn = <Offset>[];
    final hw = <double>[];
    for (var i = k0; i < s.center.length; i++) {
      final a = s.dist[i];
      final double thick;
      if (outer) {
        thick = math.max(
          math.min(_lineHalf, 0.018 * a) * g.s,
          _minLinePx * math.min(1.0, a / 80),
        );
      } else {
        final r = math.min(1.0, math.max(0.0, (a - _gapStart) / 70));
        thick = math.max(_lineHalf * r * g.s, _minLinePx * r);
      }
      final k = a > _stripEnd ? math.min(1.0, s.half[i] / s.half[_steps]) : 1.0;
      final tp = thick * k;
      final sign = outer ? side : -side;
      c.add(s.center[i] + s.nrm[i] * (sign * (s.half[i] - tp)));
      nn.add(s.nrm[i]);
      hw.add(tp * mul);
    }
    return _ribbon(c, nn, hw);
  }

  int _gapIndex(_Strip s) => s.dist.indexWhere((a) => a >= _gapStart);

  Path _gapPath(_Strip up, _Strip lo) {
    final k0 = _gapIndex(up);
    final path = Path();
    for (var i = k0; i < up.center.length; i++) {
      final p = up.center[i] + up.nrm[i] * up.half[i];
      if (i == k0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    for (var i = lo.center.length - 1; i >= k0; i--) {
      final p = lo.center[i] - lo.nrm[i] * lo.half[i];
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  Path _ribbon(List<Offset> c, List<Offset> n, List<double> hw) {
    final path = Path();
    final last = c.length - 1;
    for (var i = 0; i <= last; i++) {
      final p = c[i] - n[i] * hw[i];
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    if (hw[last] > 0.01) {
      final t = Offset(-n[last].dy, n[last].dx);
      const caps = 8;
      for (var k = 1; k < caps; k++) {
        final phi = math.pi * k / caps;
        final p = c[last] + (n[last] * -math.cos(phi) + t * math.sin(phi)) * hw[last];
        path.lineTo(p.dx, p.dy);
      }
    }
    for (var i = last; i >= 0; i--) {
      final p = c[i] + n[i] * hw[i];
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    return path;
  }

  void _paintSwirls(Canvas canvas, _Grid g) {
    final center = g.p(_swCenter);
    final stops = [for (final a in _swAng) a / 360];
    final fill = ui.Gradient.sweep(
      center,
      [for (final c in _swFill) _rgba(c, 1)],
      stops,
    );
    ui.Shader lineAt(double a) => ui.Gradient.sweep(
          center,
          [for (final c in _swLine) _rgba(c, a)],
          stops,
        );

    _drawSwirl(
      canvas,
      g,
      _swRuns(_swLens, g),
      0,
      _solid(0x6B46BE, 1),
      (a) => _solid(0xA98BEA, a),
    );

    final ribbonPts = <List<double>>[
      ..._swWisp.reversed,
      ..._swLoop.skip(1),
      ..._swRight.skip(1),
    ];
    _drawSwirl(canvas, g, _swRuns(ribbonPts, g), _swGap, fill, lineAt, core: _swCore);
  }

  List<_Curve> _swRuns(List<List<double>> pts, _Grid g) {
    final runs = <_Curve>[];
    var cur = <List<double>>[];
    for (var i = 0; i < pts.length; i++) {
      cur.add(pts[i]);
      if (i + 1 < pts.length && pts[i][2] == 0 && pts[i + 1][2] == 0) {
        runs.add(_swCurve(cur, g));
        cur = <List<double>>[];
      }
    }
    runs.add(_swCurve(cur, g));
    return runs;
  }

  _Curve _swCurve(List<List<double>> p, _Grid g) {
    final n = p.length;
    final c = <Offset>[];
    final nr = <Offset>[];
    final hw = <double>[];
    for (var i = 0; i < n - 1; i++) {
      final p1 = p[i];
      final p2 = p[i + 1];
      final p0 = i == 0
          ? <double>[2 * p1[0] - p2[0], 2 * p1[1] - p2[1], 2 * p1[2] - p2[2]]
          : p[i - 1];
      final p3 = i == n - 2
          ? <double>[2 * p2[0] - p1[0], 2 * p2[1] - p1[1], 2 * p2[2] - p1[2]]
          : p[i + 2];
      final b1 = <double>[for (var k = 0; k < 3; k++) p1[k] + (p2[k] - p0[k]) / 6];
      final b2 = <double>[for (var k = 0; k < 3; k++) p2[k] - (p3[k] - p1[k]) / 6];
      final last = i == n - 2 ? _swPer : _swPer - 1;
      for (var j = 0; j <= last; j++) {
        final t = j / _swPer;
        final u = 1 - t;
        final a0 = u * u * u;
        final a1 = 3 * u * u * t;
        final a2 = 3 * u * t * t;
        final a3 = t * t * t;
        final x = a0 * p1[0] + a1 * b1[0] + a2 * b2[0] + a3 * p2[0];
        final y = a0 * p1[1] + a1 * b1[1] + a2 * b2[1] + a3 * p2[1];
        final w = a0 * p1[2] + a1 * b1[2] + a2 * b2[2] + a3 * p2[2];
        final dx = 3 * u * u * (b1[0] - p1[0]) +
            6 * u * t * (b2[0] - b1[0]) +
            3 * t * t * (p2[0] - b2[0]);
        final dy = 3 * u * u * (b1[1] - p1[1]) +
            6 * u * t * (b2[1] - b1[1]) +
            3 * t * t * (p2[1] - b2[1]);
        final len = math.max(math.sqrt(dx * dx + dy * dy), 1e-9);
        c.add(g.p(Offset(x, y)));
        nr.add(Offset(dy / len, -dx / len));
        hw.add(math.max(0.0, w) * g.s);
      }
    }
    return _Curve(c, nr, hw);
  }

  Path _swPath(
    List<_Curve> runs,
    double Function(double h) off,
    double Function(double h) half,
  ) {
    final path = Path();
    for (final k in runs) {
      final c = <Offset>[];
      final hw = <double>[];
      for (var i = 0; i < k.c.length; i++) {
        c.add(k.c[i] + k.n[i] * off(k.h[i]));
        hw.add(math.max(0.0, half(k.h[i])));
      }
      path.addPath(_ribbon(c, k.n, hw), Offset.zero);
    }
    return path;
  }

  void _drawSwirl(
    Canvas canvas,
    _Grid g,
    List<_Curve> runs,
    double gap,
    ui.Shader fill,
    ui.Shader Function(double alpha) lineAt, {
    double core = 0,
  }) {
    final lineMax = math.max(_lineHalf * g.s, _minLinePx);
    double lh(double h) => math.min(lineMax, _swLineFrac * h);

    canvas.saveLayer(g.bounds, Paint());
    for (final glow in _swGlows) {
      canvas.drawPath(
        _swPath(runs, (h) => 0.0, (h) => h * glow.mul),
        Paint()
          ..shader = lineAt(glow.alpha)
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            math.max(glow.sigma * g.s, glow.minSigmaPx),
          ),
      );
    }
    if (gap > 0 && _gapCut > 0) {
      canvas.drawPath(
        _swPath(
          runs,
          (h) => 0.0,
          (h) => gap * h + 0.5 * g.s * math.min(1.0, h / (4 * g.s)),
        ),
        Paint()
          ..blendMode = BlendMode.dstOut
          ..color = Color.fromRGBO(0, 0, 0, _gapCut)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.5 * g.s, 0.5)),
      );
    }
    canvas.restore();

    final strands = Path();
    if (gap > 0) {
      for (final side in const [-1.0, 1.0]) {
        strands.addPath(
          _swPath(runs, (h) => side * h * (1 + gap) / 2, (h) => h * (1 - gap) / 2),
          Offset.zero,
        );
      }
    } else {
      strands.addPath(_swPath(runs, (h) => 0.0, (h) => h), Offset.zero);
    }
    canvas.drawPath(strands, Paint()..shader = fill);

    if (core > 0) {
      canvas.drawPath(
        _swPath(runs, (h) => 0.0, (h) => h * core),
        Paint()
          ..shader = lineAt(0.7)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(1.6 * g.s, 0.5)),
      );
    }

    final lines = Path();
    for (final side in const [-1.0, 1.0]) {
      lines.addPath(_swPath(runs, (h) => side * (h - lh(h)), lh), Offset.zero);
      if (gap > 0) {
        lines.addPath(
          _swPath(runs, (h) => side * (gap * h + lh(h)), (h) => lh(h) * 0.9),
          Offset.zero,
        );
      }
    }
    canvas.drawPath(lines, Paint()..shader = lineAt(1));
  }

  static ui.Shader _solid(int rgb, double a) {
    final c = _rgba(rgb, a);
    return ui.Gradient.linear(Offset.zero, const Offset(1, 0), [c, c]);
  }

  static Color _rgba(int rgb, double a) =>
      Color.fromRGBO((rgb >> 16) & 0xFF, (rgb >> 8) & 0xFF, rgb & 0xFF, a);

  static List<Color> _ramp(List<int> rgb, List<double> alpha, [double k = 1]) => [
        for (var i = 0; i < rgb.length; i++)
          _rgba(rgb[i], math.min(1.0, alpha[i] * k)),
      ];
}

class _Grid {
  _Grid(this.size, double pad) {
    final side = math.min(size.width, size.height);
    final inner = side * (1 - 2 * pad);
    s = inner / 1000;
    ox = (size.width - inner) / 2;
    oy = (size.height - inner) / 2;
  }

  final Size size;
  late final double s;
  late final double ox;
  late final double oy;

  Offset p(Offset v) => Offset(ox + v.dx * s, oy + v.dy * s);

  Rect get bounds => (Offset.zero & size).inflate(size.shortestSide * 0.4);
}

class _Strip {
  const _Strip(this.center, this.nrm, this.half, this.dist);

  final List<Offset> center;
  final List<Offset> nrm;
  final List<double> half;
  final List<double> dist;
}

class _Glow {
  const _Glow(this.mul, this.sigma, this.minSigmaPx, this.alpha);

  final double mul;
  final double sigma;
  final double minSigmaPx;
  final double alpha;
}

class _Curve {
  const _Curve(this.c, this.n, this.h);

  final List<Offset> c;
  final List<Offset> n;
  final List<double> h;
}

class _Deco {
  const _Deco(this.pts, this.gap, this.from, this.to, this.stops, this.fill);

  final List<List<double>> pts;
  final double gap;
  final Offset from;
  final Offset to;
  final List<double> stops;
  final List<int> fill;
}
