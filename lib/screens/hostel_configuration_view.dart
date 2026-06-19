import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Ensure you have this package

class HostelConfigurationView extends StatefulWidget {
  final String collegeId;

  const HostelConfigurationView({super.key, required this.collegeId});

  @override
  State<HostelConfigurationView> createState() =>
      _HostelConfigurationViewState();
}

class _HostelConfigurationViewState extends State<HostelConfigurationView> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _hostelsController = TextEditingController(
    text: '1',
  );
  final TextEditingController _roomsController = TextEditingController(
    text: '10',
  );
  final TextEditingController _capacityController = TextEditingController(
    text: '2',
  );

  bool _isGenerating = false;

  Future<void> _generateHostelInfrastructure() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.collegeId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error: College ID is missing.')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
    });

    try {
      int numHostels = int.parse(_hostelsController.text.trim());
      int numRooms = int.parse(_roomsController.text.trim());
      int capacity = int.parse(_capacityController.text.trim());

      final firestore = FirebaseFirestore.instance;

      // Reference to the specific college's hostels subcollection
      CollectionReference hostelsRef = firestore
          .collection('colleges')
          .doc(widget.collegeId)
          .collection('hostels');

      // Note: We use standard loops here instead of WriteBatch to avoid the
      // 500 document limit if "n" is a very large number.
      for (int h = 1; h <= numHostels; h++) {
        String hostelId = 'Hostel_$h';

        // 1. Create the Hostel Document
        await hostelsRef.doc(hostelId).set({
          'hostelName': 'Hostel $h',
          'totalRooms': numRooms,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 2. Create the Rooms Subcollection for this specific Hostel
        for (int r = 1; r <= numRooms; r++) {
          String roomId = 'Room_$r';

          await hostelsRef.doc(hostelId).collection('rooms').doc(roomId).set({
            'roomNumber': '$r',
            'maxCapacity': capacity,
            'currentOccupants': 0, // Defaults to 0 when generated
            'students': [], // Array to hold student UIDs later
          });
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hostel infrastructure generated successfully!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error generating structure: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _hostelsController.dispose();
    _roomsController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Hostel Infrastructure Setup',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Define the architecture of your college hostels. This will automatically generate the database collections.',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Inputs Row
              Row(
                children: [
                  Expanded(
                    child: _buildInputField(
                      controller: _hostelsController,
                      label: 'Number of Hostels',
                      icon: Icons.domain,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      controller: _roomsController,
                      label: 'Rooms per Hostel',
                      icon: Icons.meeting_room,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildInputField(
                      controller: _capacityController,
                      label: 'Capacity per Room',
                      icon: Icons.people_alt,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 40),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isGenerating
                      ? null
                      : _generateHostelInfrastructure,
                  child: _isGenerating
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Generate Collections',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return 'Required';
        if (int.tryParse(value) == null || int.parse(value) <= 0) {
          return 'Enter a valid number > 0';
        }
        return null;
      },
    );
  }
}
