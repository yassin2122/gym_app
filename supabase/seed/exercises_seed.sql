-- Starter exercise seed data. Real exercises with accurate muscle/
-- equipment metadata — a subset of the eventual ~150, not fabricated
-- placeholder data. Expand this file as more exercises are added.
insert into public.exercises (name, primary_muscle, secondary_muscles, equipment, exercise_type, instructions) values
  ('Barbell Bench Press', 'chest', array['triceps','shoulders'], 'barbell', 'strength', 'Lie flat on a bench with feet planted. Grip the bar slightly wider than shoulder width. Lower to mid-chest, then press up to full extension.'),
  ('Incline Dumbbell Press', 'chest', array['shoulders','triceps'], 'dumbbell', 'strength', 'Set bench to a 30-45 degree incline. Press dumbbells from shoulder level to full extension above the chest.'),
  ('Cable Fly', 'chest', array['shoulders'], 'cable', 'strength', 'Stand between two cable stacks. Bring handles together in front of the chest with a slight bend in the elbows.'),
  ('Push-Up', 'chest', array['triceps','shoulders','core'], 'bodyweight', 'strength', 'Start in a plank position. Lower the chest to the floor, then press back up while keeping the body straight.'),
  ('Deadlift', 'back', array['glutes','hamstrings','core'], 'barbell', 'strength', 'Stand with feet hip-width apart, bar over mid-foot. Hinge at the hips, grip the bar, and drive through the floor to stand tall.'),
  ('Pull-Up', 'back', array['biceps','shoulders'], 'bodyweight', 'strength', 'Hang from a bar with an overhand grip. Pull the chest toward the bar, then lower with control.'),
  ('Barbell Row', 'back', array['biceps','shoulders'], 'barbell', 'strength', 'Hinge forward with a flat back. Pull the bar toward the lower ribs, squeezing the shoulder blades together.'),
  ('Lat Pulldown', 'back', array['biceps','shoulders'], 'cable', 'strength', 'Sit with thighs secured. Pull the bar down to the upper chest, then extend arms with control.'),
  ('Seated Cable Row', 'back', array['biceps','shoulders'], 'cable', 'strength', 'Sit with knees slightly bent. Pull the handle to the torso, squeezing the shoulder blades together.'),
  ('Barbell Back Squat', 'legs', array['glutes','core'], 'barbell', 'strength', 'Bar rests on the upper back. Squat down until thighs are parallel to the floor, then drive back up.'),
  ('Romanian Deadlift', 'legs', array['glutes','back'], 'barbell', 'strength', 'Keep a slight knee bend, hinge at the hips lowering the bar along the legs, then return to standing.'),
  ('Leg Press', 'legs', array['glutes'], 'machine', 'strength', 'Sit in the machine with feet shoulder-width on the platform. Lower until knees reach 90 degrees, then press back up.'),
  ('Walking Lunge', 'legs', array['glutes','core'], 'dumbbell', 'strength', 'Step forward into a lunge, lowering the back knee toward the floor, then bring the back leg through to the next step.'),
  ('Leg Curl', 'legs', array[]::text[], 'machine', 'strength', 'Lie face down on the machine. Curl the heels toward the glutes, then lower with control.'),
  ('Calf Raise', 'legs', array[]::text[], 'machine', 'strength', 'Stand on the platform with heels hanging off. Raise onto the toes, then lower below parallel.'),
  ('Overhead Press', 'shoulders', array['triceps','core'], 'barbell', 'strength', 'Stand with the bar at shoulder height. Press overhead to full extension, then lower with control.'),
  ('Lateral Raise', 'shoulders', array[]::text[], 'dumbbell', 'strength', 'Stand with dumbbells at the sides. Raise arms out to shoulder height, then lower slowly.'),
  ('Face Pull', 'shoulders', array['back'], 'cable', 'strength', 'Pull the rope toward the face, flaring elbows out and squeezing the rear shoulders.'),
  ('Barbell Curl', 'arms', array[]::text[], 'barbell', 'strength', 'Stand holding the bar with an underhand grip. Curl to shoulder height, then lower with control.'),
  ('Tricep Pushdown', 'arms', array[]::text[], 'cable', 'strength', 'Stand facing the cable stack. Push the bar down to full extension, keeping elbows tucked.'),
  ('Hammer Curl', 'arms', array[]::text[], 'dumbbell', 'strength', 'Hold dumbbells with a neutral grip. Curl to shoulder height without rotating the wrist.'),
  ('Plank', 'core', array[]::text[], 'bodyweight', 'strength', 'Hold a forearm plank position with a straight line from head to heels, bracing the core throughout.'),
  ('Hanging Leg Raise', 'core', array[]::text[], 'bodyweight', 'strength', 'Hang from a bar. Raise the legs to hip height or higher, then lower with control.'),
  ('Treadmill Run', 'legs', array['core'], 'machine', 'cardio', 'Maintain a steady pace appropriate to your fitness level; adjust incline for added intensity.');
