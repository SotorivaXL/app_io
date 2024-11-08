import 'package:flutter/material.dart';

class CustomDropdownButton<T> extends StatelessWidget {
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String hint;

  CustomDropdownButton({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        fillColor: Theme.of(context).colorScheme.primary, // Cor de fundo do DropdownButton
        filled: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 5),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary),
          borderRadius: BorderRadius.circular(25),
        ),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.primary, width: 2),
          borderRadius: BorderRadius.circular(25),
        ),
        errorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error),
          borderRadius: BorderRadius.circular(25),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 2),
          borderRadius: BorderRadius.circular(25),
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          dropdownColor: Theme.of(context).colorScheme.primary,
          value: value,
          items: items,
          onChanged: onChanged,
          hint: Text(
            hint,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 10,
              color: Theme.of(context).colorScheme.outline
            ),
          ),
          style: TextStyle(
            fontSize: 12,
            fontFamily: 'Poppins',
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.outline,
          ),
          icon: SizedBox.shrink(), // Remove o ícone
        ),
      ),
    );
  }
}
