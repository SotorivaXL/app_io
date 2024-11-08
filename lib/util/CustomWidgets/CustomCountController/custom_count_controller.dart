import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class CustomCountController extends StatelessWidget {
  final int count;
  final ValueChanged<int> updateCount;
  final int stepSize;

  CustomCountController({
    required this.count,
    required this.updateCount,
    this.stepSize = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.0),
      height: 50,  // Definindo uma altura fixa para alinhar verticalmente
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme.of(context).primaryColor,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          IconButton(
            icon: FaIcon(
              FontAwesomeIcons.minus,
              color: count > 0
                  ? Theme.of(context).colorScheme.tertiary
                  : Theme.of(context).colorScheme.onSurface.withOpacity(0.38),
              size: 20,
            ),
            onPressed: count > 0
                ? () => updateCount(count - stepSize)
                : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0),
            child: Text(
              count.toString(),
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w500,
                fontSize: 16,
                letterSpacing: 0,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
          ),
          IconButton(
            icon: FaIcon(
              FontAwesomeIcons.plus,
              color: Theme.of(context).colorScheme.tertiary,
              size: 20,
            ),
            onPressed: () => updateCount(count + stepSize),
          ),
        ],
      ),
    );
  }
}
