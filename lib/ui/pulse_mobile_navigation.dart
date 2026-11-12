import 'package:flutter/material.dart';

enum PulseMobileTab { home, search, library }

class PulseMobileNavigation extends StatelessWidget {
  const PulseMobileNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final PulseMobileTab selected;
  final ValueChanged<PulseMobileTab> onSelect;

  @override
  Widget build(BuildContext context) {
    const items = [
      (PulseMobileTab.home, Icons.home_outlined, Icons.home_rounded, 'Início'),
      (
        PulseMobileTab.search,
        Icons.search_rounded,
        Icons.search_rounded,
        'Buscar'
      ),
      (
        PulseMobileTab.library,
        Icons.library_music_outlined,
        Icons.library_music_rounded,
        'Biblioteca'
      ),
    ];
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0xB8000000), Color(0xED000000)],
          stops: [0, .42, 1],
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final item in items)
                Expanded(
                  child: Semantics(
                    selected: selected == item.$1,
                    button: true,
                    label: item.$4,
                    child: InkWell(
                      onTap: () => onSelect(item.$1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            selected == item.$1 ? item.$3 : item.$2,
                            size: 23,
                            color: selected == item.$1
                                ? Colors.white
                                : Colors.white60,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            item.$4,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: selected == item.$1
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: selected == item.$1
                                  ? Colors.white
                                  : Colors.white60,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
