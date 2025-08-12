import 'dart:convert';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_typeahead/flutter_typeahead.dart';
import 'package:http/http.dart' as http;

const String kGoogleApiKey = 'YOUR_VALID_GOOGLE_API_KEY';

/// Modelo para sugestão de local
class PlaceSuggestion {
  final String description;
  final String placeId;

  PlaceSuggestion({required this.description, required this.placeId});

  factory PlaceSuggestion.fromJson(Map<String, dynamic> json) {
    return PlaceSuggestion(
      description: json['description'] as String,
      placeId: json['place_id'] as String,
    );
  }
}

/// Função para buscar sugestões usando a nova API Places com App Check
Future<List<PlaceSuggestion>> fetchPlaceSuggestions(String query) async {
  if (query.isEmpty) return [];
  // Obtém o token do Firebase App Check (caso seja nulo, usamos string vazia)
  final appCheckToken = await FirebaseAppCheck.instance.getToken() ?? "";
  final url =
      "https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${Uri.encodeComponent(query)}&key=$kGoogleApiKey&language=pt_BR";
  final response = await http.get(
    Uri.parse(url),
    headers: {"X-Firebase-AppCheck": appCheckToken},
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['status'] == "OK") {
      final List predictions = data['predictions'];
      return predictions
          .map((json) => PlaceSuggestion.fromJson(json))
          .toList();
    } else {
      return [];
    }
  } else {
    throw Exception("Failed to fetch suggestions");
  }
}

/// Função para buscar detalhes do local e retornar a coordenada (LatLng)
Future<LatLng?> fetchPlaceDetail(String placeId) async {
  final appCheckToken = await FirebaseAppCheck.instance.getToken() ?? "";
  final url =
      "https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$kGoogleApiKey&language=pt_BR";
  final response = await http.get(
    Uri.parse(url),
    headers: {"X-Firebase-AppCheck": appCheckToken},
  );
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['status'] == "OK") {
      final location = data['result']['geometry']['location'];
      return LatLng(location['lat'], location['lng']);
    } else {
      return null;
    }
  } else {
    throw Exception("Failed to fetch place detail");
  }
}

class CustomMapPicker extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final Function(double latitude, double longitude) onLocationPicked;

  const CustomMapPicker({
    Key? key,
    required this.initialLatitude,
    required this.initialLongitude,
    required this.onLocationPicked,
  }) : super(key: key);

  @override
  _CustomMapPickerState createState() => _CustomMapPickerState();
}

class _CustomMapPickerState extends State<CustomMapPicker> {
  late GoogleMapController _mapController;
  late LatLng _pickedLocation;
  double _scrollOffset = 0.0;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _pickedLocation =
        LatLng(widget.initialLatitude, widget.initialLongitude);
  }

  void _onMapCreated(GoogleMapController controller) {
    _mapController = controller;
  }

  // Obtém a localização atual utilizando Geolocator
  Future<void> _selectCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Serviço de localização desabilitado.')),
      );
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Permissão de localização negada.')),
        );
        return;
      }
    }
    if (permission == LocationPermission.deniedForever) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
            Text('Permissão de localização negada permanentemente.')),
      );
      return;
    }

    Position position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );

    widget.onLocationPicked(position.latitude, position.longitude);
    Navigator.pop(context);
  }

  // Retorna a localização pré-definida do IO Marketing Digital
  void _selectIOMarketing() {
    widget.onLocationPicked(-25.91562067235313, -53.47482542697126);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    double appBarHeight =
    (100.0 - (_scrollOffset / 2)).clamp(0.0, 100.0);

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: appBarHeight,
        automaticallyImplyLeading: false,
        flexibleSpace: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Botão de voltar e título
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.arrow_back_ios_new,
                            color:
                            Theme.of(context).colorScheme.onBackground,
                            size: 18,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Voltar',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Selecione a localização',
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context)
                            .colorScheme
                            .onSecondary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        surfaceTintColor: Colors.transparent,
        backgroundColor: Theme.of(context).colorScheme.secondary,
      ),
      body: Stack(
        children: [
          GoogleMap(
            onMapCreated: _onMapCreated,
            initialCameraPosition: CameraPosition(
              target: _pickedLocation,
              zoom: 15,
            ),
            markers: {
              Marker(
                markerId: const MarkerId("picked"),
                position: _pickedLocation,
                draggable: true,
                onDragEnd: (newPosition) {
                  setState(() {
                    _pickedLocation = newPosition;
                  });
                },
              ),
            },
            onTap: (latLng) {
              setState(() {
                _pickedLocation = latLng;
              });
            },
          ),
          // BottomSheet persistente com as opções de localização
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary,
                borderRadius:
                const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: _selectCurrentLocation,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.my_location,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Localização atual',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 40,
                    color: Colors.white54,
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: _selectIOMarketing,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.location_on,
                            color:
                            Theme.of(context).colorScheme.onSecondary,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'IO Marketing Digital',
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontSize: 14,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Botão para confirmar a seleção, posicionado acima do BottomSheet
          Positioned(
            bottom: 96,
            left: 16,
            right: 16,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
              onPressed: () {
                widget.onLocationPicked(
                  _pickedLocation.latitude,
                  _pickedLocation.longitude,
                );
                Navigator.pop(context);
              },
              child: Text(
                "Usar esta localização",
                style: TextStyle(
                  color: Theme.of(context).colorScheme.outline,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}