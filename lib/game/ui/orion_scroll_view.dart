import 'package:flutter/material.dart';

class OrionScrollView extends StatefulWidget {
  const OrionScrollView({super.key, required this.child, this.padding});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  State<OrionScrollView> createState() => _OrionScrollViewState();
}

class _OrionScrollViewState extends State<OrionScrollView> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scrollbar(
    controller: _controller,
    thumbVisibility: true,
    child: SingleChildScrollView(
      controller: _controller,
      padding: widget.padding,
      child: widget.child,
    ),
  );
}
