import 'package:flutter/material.dart';

class CheckBoxGroupWidget extends StatefulWidget {
  @override
  _CheckBoxGroupWidgetState createState() => _CheckBoxGroupWidgetState();
}

class _CheckBoxGroupWidgetState extends State<CheckBoxGroupWidget> {
  final List<String> options = ['Dashboard', 'Leads', 'Gerenciar colaboradores'];
  List<bool> selectedValues = [false, false, false];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(options.length, (index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 0.0), // Menor espaçamento vertical
          child: Row(
            children: [
              Transform.scale(
                scale: 1.2, // Aumenta o tamanho do checkbox para facilitar a visualização
                child: Checkbox(
                  checkColor: Theme.of(context).colorScheme.outline,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(5.0), // Arredonda os cantos do checkbox
                  ),
                  activeColor: Theme.of(context).primaryColor,
                  value: selectedValues[index],
                  onChanged: (bool? value) {
                    setState(() {
                      selectedValues[index] = value!;
                    });
                  },
                ),
              ),
              SizedBox(width: 0.0), // Espaçamento horizontal entre checkbox e texto
              Expanded(
                child: Text(
                  options[index],
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w500,
                    fontSize: 16,
                    color: Theme.of(context).colorScheme.onSecondary,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
