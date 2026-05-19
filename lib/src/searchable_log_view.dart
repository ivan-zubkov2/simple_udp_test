import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SearchIntent extends Intent {
  const SearchIntent();
}

class SearchableLogView extends StatefulWidget {
  const SearchableLogView({
    super.key,
    required this.controller,
    required this.scrollController,
  });

  final TextEditingController controller;
  final ScrollController scrollController;

  @override
  State<SearchableLogView> createState() => SearchableLogViewState();
}

class SearchableLogViewState extends State<SearchableLogView> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final FocusNode _logFocusNode = FocusNode();
  bool _searchVisible = false;
  String _statusText = '';

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _logFocusNode.dispose();
    super.dispose();
  }

  void openSearch() {
    setState(() {
      _searchVisible = true;
      _statusText = _searchController.text.isEmpty ? '' : _statusText;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _searchFocusNode.requestFocus();
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _closeSearch() {
    setState(() {
      _searchVisible = false;
      _statusText = '';
    });
  }

  void _onSearchChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _statusText = '';
      });
      return;
    }

    _findNext(fromStart: true);
  }

  void _findNext({bool fromStart = false}) {
    final query = _searchController.text;
    final source = widget.controller.text;

    if (query.isEmpty || source.isEmpty) {
      setState(() {
        _statusText = query.isEmpty ? '' : 'No matches';
      });
      return;
    }

    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final selection = widget.controller.selection;
    final startIndex =
        fromStart
            ? 0
            : (selection.isValid ? selection.end.clamp(0, source.length) : 0);

    var matchIndex = lowerSource.indexOf(lowerQuery, startIndex);
    if (matchIndex == -1 && startIndex > 0) {
      matchIndex = lowerSource.indexOf(lowerQuery);
    }

    _applyMatch(matchIndex, query.length);
  }

  void _findPrevious() {
    final query = _searchController.text;
    final source = widget.controller.text;

    if (query.isEmpty || source.isEmpty) {
      setState(() {
        _statusText = query.isEmpty ? '' : 'No matches';
      });
      return;
    }

    final lowerSource = source.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final selection = widget.controller.selection;
    final startIndex =
        selection.isValid
            ? (selection.start - 1).clamp(0, source.length - 1)
            : source.length - 1;

    var matchIndex = lowerSource.lastIndexOf(lowerQuery, startIndex);
    if (matchIndex == -1 && startIndex < source.length - 1) {
      matchIndex = lowerSource.lastIndexOf(lowerQuery);
    }

    _applyMatch(matchIndex, query.length);
  }

  void _applyMatch(int matchIndex, int queryLength) {
    if (matchIndex == -1) {
      setState(() {
        _statusText = 'No matches';
      });
      return;
    }

    widget.controller.selection = TextSelection(
      baseOffset: matchIndex,
      extentOffset: matchIndex + queryLength,
    );

    setState(() {
      _statusText = 'Match at ${matchIndex + 1}';
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _logFocusNode.requestFocus();
      _searchFocusNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (_searchVisible)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    onChanged: _onSearchChanged,
                    onSubmitted: (_) => _findNext(),
                    decoration: const InputDecoration(
                      labelText: 'Find in log',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _findPrevious,
                  tooltip: 'Previous match',
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  onPressed: _findNext,
                  tooltip: 'Next match',
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  onPressed: _closeSearch,
                  tooltip: 'Close search',
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        if (_searchVisible && _statusText.isNotEmpty)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_statusText),
            ),
          ),
        Expanded(
          child: TextField(
            controller: widget.controller,
            scrollController: widget.scrollController,
            focusNode: _logFocusNode,
            readOnly: true,
            expands: true,
            maxLines: null,
            textAlignVertical: TextAlignVertical.top,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
