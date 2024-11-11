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
    return SizedBox(
      height: 60, // Define uma altura para evitar problemas de layout
      child: InputDecorator(
        decoration: InputDecoration(
          fillColor: Theme.of(context).colorScheme.primary, // Cor de fundo do DropdownButton
          filled: true,
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
            iconSize: 0.0,
            alignment: Alignment.center, // Alinha o valor selecionado à esquerda
            dropdownColor: Theme.of(context).colorScheme.primary,
            value: value,
            items: items,
            onChanged: onChanged,
            hint: Align(
              alignment: Alignment.center,
              child: Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 10,
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
            ),
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.outline,
            ),
            isDense: true, // Torna o dropdown mais compacto
            itemHeight: 50,
            selectedItemBuilder: (BuildContext context) {
              return items.map<Widget>((DropdownMenuItem<T> item) {
                return Align(
                  alignment: Alignment.center, // Alinha as opções à esquerda
                  child: item.child,
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
