import 'package:flutter/material.dart';

void showErrorDialog(BuildContext context, String message, String title) {
  FocusScope.of(context).unfocus();

  var colorTitle = Theme.of(context).colorScheme.onSecondary;

  if (title == "Erro") {
    colorTitle = Theme.of(context).colorScheme.error;
  } else if (title == "Sucesso") {
    colorTitle = Theme.of(context).colorScheme.onTertiary;
  } else if (title == "Atenção") {
    colorTitle = Color(0xffdc9f21);
  }

  showModalBottomSheet(
    context: context,
    shape: RoundedRectangleBorder(
      side: BorderSide(
        color: Theme.of(context).primaryColor,
        width: 2,
      ),
      borderRadius: BorderRadius.vertical(top: Radius.circular(25.0)),
    ),
    backgroundColor: Theme.of(context).colorScheme.background,
    builder: (BuildContext context) {
      return Container(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  color: colorTitle),
            ),
            SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 16,
                color: Theme.of(context).colorScheme.onSecondary,
              ),
            ),
            SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  child: Text(
                    'Entendi',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}