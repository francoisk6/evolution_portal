import 'package:flutter/material.dart';
import '../widgets/page_background.dart';

class AuthScaffold extends StatelessWidget {
  final Widget child;
  const AuthScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          const PageBackground(child: SizedBox.expand()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Allow the auth card to scroll on smaller screens / long forms,
                // while staying vertically centered when there is enough space.
                final minH = (constraints.maxHeight - 32).clamp(0.0, double.infinity);
                return SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: minH),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
