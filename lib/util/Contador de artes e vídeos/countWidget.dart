// Widget _buildWeeklyContent() {
//   return Column(
//     children: [
//       Padding(
//         padding: const EdgeInsetsDirectional.fromSTEB(0, 20, 0, 0),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Padding(
//               padding: const EdgeInsetsDirectional.fromSTEB(20, 10, 20, 10),
//               child: Text(
//                 'Quantidade de conteúdo semanal:',
//                 style: TextStyle(
//                   fontFamily: 'Poppins',
//                   fontSize: 18,
//                   fontWeight: FontWeight.w600,
//                   color: Theme.of(context).colorScheme.onSecondary,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//       // Artes
//       Padding(
//         padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             const Padding(
//               padding: EdgeInsetsDirectional.fromSTEB(30, 0, 0, 0),
//               child: Text(
//                 'Artes',
//                 style: TextStyle(
//                   fontFamily: 'Poppins',
//                   fontWeight: FontWeight.w500,
//                   fontSize: 14,
//                 ),
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 20, 0),
//               child: CustomCountController(
//                 count: _model.countArtsValue,
//                 updateCount: updateCountArts,
//               ),
//             ),
//           ],
//         ),
//       ),
//       // Vídeos
//       Padding(
//         padding: const EdgeInsetsDirectional.fromSTEB(0, 10, 0, 0),
//         child: Row(
//           mainAxisAlignment: MainAxisAlignment.spaceBetween,
//           children: [
//             const Padding(
//               padding: EdgeInsetsDirectional.fromSTEB(30, 0, 0, 0),
//               child: Text(
//                 'Vídeos',
//                 style: TextStyle(
//                   fontFamily: 'Poppins',
//                   fontWeight: FontWeight.w500,
//                   fontSize: 14,
//                 ),
//               ),
//             ),
//             Padding(
//               padding: const EdgeInsetsDirectional.fromSTEB(0, 0, 20, 0),
//               child: CustomCountController(
//                 count: _model.countVideosValue,
//                 updateCount: updateCountVideos,
//               ),
//             ),
//           ],
//         ),
//       ),
//     ],
//   );
// }